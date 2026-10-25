#include "download_hls.h"

#include <curl/curl.h>
#include <mbedtls/aes.h>
#include <mbedtls/platform_util.h>

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <limits>
#include <map>
#include <set>
#include <sstream>

namespace aira::download {
namespace {

std::string Trim(const std::string& value) {
  const auto first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) return {};
  return value.substr(first, value.find_last_not_of(" \t\r\n") - first + 1);
}

std::string ResolveUrl(const std::string& base, const std::string& reference) {
  CURLU* url = curl_url();
  if (url == nullptr) return {};
  char* resolved = nullptr;
  const bool ok = curl_url_set(url, CURLUPART_URL, base.c_str(), 0) == CURLUE_OK &&
    curl_url_set(url, CURLUPART_URL, reference.c_str(), 0) == CURLUE_OK &&
    curl_url_get(url, CURLUPART_URL, &resolved, 0) == CURLUE_OK && resolved != nullptr;
  const std::string result = ok ? resolved : "";
  curl_free(resolved);
  curl_url_cleanup(url);
  return result;
}

std::map<std::string, std::string> Attributes(const std::string& line) {
  std::map<std::string, std::string> result;
  std::size_t position = line.find(':');
  if (position == std::string::npos) return result;
  ++position;
  while (position < line.size()) {
    const std::size_t equals = line.find('=', position);
    if (equals == std::string::npos) break;
    const std::string name = Trim(line.substr(position, equals - position));
    position = equals + 1;
    const bool quoted = position < line.size() && line[position] == '"';
    if (quoted) ++position;
    const auto end = line.find(quoted ? '"' : ',', position);
    result[name] = line.substr(position, end == std::string::npos ? end : end - position);
    if (end == std::string::npos) break;
    position = end + 1;
    if (quoted && position < line.size() && line[position] == ',') ++position;
  }
  return result;
}

bool UnsignedInteger(const std::string& text, std::uint64_t* value) {
  if (text.empty() || text.find_first_not_of("0123456789") != std::string::npos) return false;
  try { *value = std::stoull(text); return true; } catch (...) { return false; }
}

bool ParseIv(const std::string& value, std::array<unsigned char, 16>* iv) {
  if (value.size() < 3 || value.size() > 34 || (value.substr(0, 2) != "0x" && value.substr(0, 2) != "0X")) return false;
  iv->fill(0);
  std::size_t nibble = 32 - (value.size() - 2);
  for (std::size_t index = 2; index < value.size(); ++index, ++nibble) {
    const char c = value[index];
    const int digit = c >= '0' && c <= '9' ? c - '0' :
      c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
    if (digit < 0) return false;
    (*iv)[nibble / 2] |= static_cast<unsigned char>(digit << (nibble % 2 == 0 ? 4 : 0));
  }
  return true;
}

bool SetRange(const std::string& value, std::int64_t implicit_offset, HlsResource* resource) {
  const auto at = value.find('@');
  std::uint64_t length = 0;
  std::uint64_t offset = 0;
  if (!UnsignedInteger(value.substr(0, at), &length) || length == 0) return false;
  if (at == std::string::npos) {
    if (implicit_offset < 0) return false;
    offset = static_cast<std::uint64_t>(implicit_offset);
  } else if (!UnsignedInteger(value.substr(at + 1), &offset)) {
    return false;
  }
  const auto maximum = static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max());
  if (offset > maximum || length > maximum - offset) return false;
  resource->offset = static_cast<std::int64_t>(offset);
  resource->length = static_cast<std::int64_t>(length);
  return true;
}

}  // namespace

HlsKey::~HlsKey() {
  mbedtls_platform_zeroize(bytes.data(), bytes.size());
}

HlsProgressTracker::HlsProgressTracker(const std::vector<HlsResource>& resources) {
  for (const auto& resource : resources) {
    resources_.push_back({resource.initialization, false, 0});
    if (resource.initialization) ++map_count_;
    else ++media_count_;
  }
}

void HlsProgressTracker::Update(std::size_t index, std::int64_t received, std::int64_t total) {
  if (index >= resources_.size() || resources_[index].completed) return;
  auto& resource = resources_[index];
  // Reserve the last fraction until the file has been validated and decrypted.
  const double fraction = total > 0 ? std::clamp(static_cast<double>(received) / total, 0.0, 0.99) : 0;
  completed_units_ += fraction - resource.fraction;
  resource.fraction = fraction;
}

void HlsProgressTracker::Complete(std::size_t index, std::int64_t bytes) {
  if (index >= resources_.size() || resources_[index].completed || bytes <= 0) return;
  auto& resource = resources_[index];
  completed_units_ += 1 - resource.fraction;
  resource.fraction = 1;
  resource.completed = true;
  if (resource.initialization) {
    ++completed_map_count_;
    map_bytes_ += bytes;
  } else {
    ++completed_media_count_;
    media_bytes_ += bytes;
  }
}

double HlsProgressTracker::Fraction() const {
  // Only the owning task may report 100%, after the merged file is closed.
  return resources_.empty() ? -1 : std::clamp(completed_units_ / resources_.size(), 0.0, 0.99);
}

std::int64_t HlsProgressTracker::EstimatedTotalBytes() const {
  if (completed_media_count_ == 0) return 0;
  // Tiny initialization sections must not skew the media sample average.
  const double estimate = media_bytes_ / completed_media_count_ * media_count_ +
    (completed_map_count_ > 0 ? map_bytes_ / completed_map_count_ * map_count_ : 0);
  if (estimate >= static_cast<double>(std::numeric_limits<std::int64_t>::max())) {
    return std::numeric_limits<std::int64_t>::max();
  }
  return static_cast<std::int64_t>(estimate);
}

// RFC 8216 sections 4.3.2.2, 4.3.2.4, 4.3.2.5 and 5.2. AES-128 is whole-segment
// CBC with PKCS#7; SAMPLE-AES/DRM need a demuxer and are deliberately rejected.
bool ParseHlsMedia(const std::string& playlist, const std::string& base_url,
                   HlsPlan* plan, std::vector<HlsVariant>* variants, std::string* error) {
  std::istringstream stream(playlist);
  std::string line;
  bool header = false;
  bool has_end = false;
  bool has_media = false;
  bool expect_variant = false;
  HlsVariant pending_variant;
  std::set<std::string> external_audio_groups;
  std::uint64_t sequence = 0;
  int key_index = -1;
  bool explicit_iv = false;
  std::array<unsigned char, 16> iv{};
  HlsResource active_map;
  bool has_map = false;
  bool map_pending = false;
  std::string pending_range;
  HlsResource previous_media;
  while (std::getline(stream, line)) {
    std::string value = Trim(line);
    if (!header && value.rfind("\xEF\xBB\xBF", 0) == 0) value.erase(0, 3);
    if (value.empty()) continue;
    if (!header) {
      if (value != "#EXTM3U") { *error = "HLS 清单格式无效。"; return false; }
      header = true;
      continue;
    }
    if (value.rfind("#EXT-X-MEDIA-SEQUENCE:", 0) == 0) {
      if (has_media || !UnsignedInteger(value.substr(22), &sequence)) {
        *error = "HLS 媒体序号无效。"; return false;
      }
    } else if (value.rfind("#EXT-X-MEDIA:", 0) == 0) {
      const auto attrs = Attributes(value);
      const auto type = attrs.find("TYPE"), uri = attrs.find("URI"), group = attrs.find("GROUP-ID");
      if (type != attrs.end() && type->second == "AUDIO" && uri != attrs.end() &&
          !uri->second.empty() && group != attrs.end()) external_audio_groups.insert(group->second);
    } else if (value.rfind("#EXT-X-STREAM-INF:", 0) == 0) {
      if (variants == nullptr) { *error = "暂不支持嵌套 HLS 主清单。"; return false; }
      auto attrs = Attributes(value);
      std::uint64_t bandwidth = 0;
      UnsignedInteger(attrs["BANDWIDTH"], &bandwidth);
      pending_variant = {static_cast<std::int64_t>(std::min<std::uint64_t>(
        bandwidth, std::numeric_limits<std::int64_t>::max())), "", attrs["AUDIO"], false};
      expect_variant = true;
    } else if (value.rfind("#EXT-X-KEY:", 0) == 0) {
      auto attrs = Attributes(value);
      const std::string method = attrs["METHOD"];
      if (method == "NONE") { key_index = -1; explicit_iv = false; continue; }
      if (method != "AES-128") {
        *error = "暂不支持 HLS " + method + " 加密（SAMPLE-AES/DRM）。"; return false;
      }
      if ((!attrs["KEYFORMAT"].empty() && attrs["KEYFORMAT"] != "identity") ||
          (!attrs["KEYFORMATVERSIONS"].empty() && attrs["KEYFORMATVERSIONS"] != "1")) {
        *error = "暂不支持此 HLS DRM 密钥格式。"; return false;
      }
      const std::string key_url = attrs["URI"].empty() ? "" : ResolveUrl(base_url, attrs["URI"]);
      if (key_url.empty()) { *error = "HLS AES-128 密钥地址无效。"; return false; }
      explicit_iv = !attrs["IV"].empty();
      if (explicit_iv && !ParseIv(attrs["IV"], &iv)) { *error = "HLS AES-128 IV 无效。"; return false; }
      HlsKey key;
      key.url = key_url;
      plan->keys.push_back(key);
      key_index = static_cast<int>(plan->keys.size()) - 1;
    } else if (value.rfind("#EXT-X-MAP:", 0) == 0) {
      auto attrs = Attributes(value);
      active_map = {};
      active_map.url = attrs["URI"].empty() ? "" : ResolveUrl(base_url, attrs["URI"]);
      active_map.initialization = true;
      active_map.key_index = key_index;
      active_map.iv = iv;
      if (active_map.url.empty()) { *error = "HLS 初始化分片地址无效。"; return false; }
      if (key_index >= 0 && !explicit_iv) { *error = "加密 HLS 初始化分片需要显式 IV。"; return false; }
      if (!attrs["BYTERANGE"].empty() && !SetRange(attrs["BYTERANGE"], -1, &active_map)) {
        *error = "HLS 初始化分片字节范围无效，需要显式偏移。"; return false;
      }
      has_map = true;
      map_pending = true;
      plan->fragmented_mp4 = true;
    } else if (value.rfind("#EXT-X-BYTERANGE:", 0) == 0) {
      pending_range = value.substr(17);
    } else if (value == "#EXT-X-ENDLIST") {
      has_end = true;
    } else if (value.front() != '#') {
      const std::string resolved = ResolveUrl(base_url, value);
      if (resolved.empty()) { *error = "HLS 分片地址无效。"; return false; }
      if (expect_variant) {
        pending_variant.url = resolved;
        variants->push_back(pending_variant);
        expect_variant = false;
        continue;
      }
      HlsResource resource;
      resource.url = resolved;
      resource.key_index = key_index;
      resource.iv = iv;
      if (key_index >= 0 && !explicit_iv) {
        resource.iv.fill(0);
        for (unsigned int byte = 0; byte < 8; ++byte) {
          resource.iv[15 - byte] = static_cast<unsigned char>(sequence >> (byte * 8));
        }
      }
      if (!pending_range.empty()) {
        const std::int64_t implicit = previous_media.url == resolved && previous_media.offset >= 0 ?
          previous_media.offset + previous_media.length : -1;
        if (!SetRange(pending_range, implicit, &resource)) {
          *error = "HLS 分片字节范围无效，隐式偏移需要前一段使用相同资源。"; return false;
        }
        pending_range.clear();
      }
      if (has_map && map_pending) { plan->resources.push_back(active_map); map_pending = false; }
      plan->resources.push_back(resource);
      previous_media = resource;
      has_media = true;
      if (sequence == std::numeric_limits<std::uint64_t>::max()) {
        *error = "HLS 媒体序号超出范围。"; return false;
      }
      ++sequence;
    }
  }
  if (variants != nullptr && !variants->empty()) {
    for (auto& variant : *variants) variant.external_audio = external_audio_groups.count(variant.audio_group) > 0;
    return true;
  }
  if (!header || !has_media || !pending_range.empty()) { *error = "HLS 清单中没有有效的视频分片。"; return false; }
  if (!has_end) { *error = "当前版本暂不支持直播 HLS 下载。"; return false; }
  return true;
}

bool DecryptHlsFile(const std::string& path, const HlsKey& key,
                    const std::array<unsigned char, 16>& initial_iv,
                    const std::function<bool()>& interrupted, std::string* error) {
  std::error_code fs_error;
  const auto size = std::filesystem::file_size(path, fs_error);
  if (fs_error || size == 0 || size % 16 != 0) { *error = "HLS AES-128 密文长度无效。"; return false; }
  const std::string temporary = path + ".decrypt";
  std::ifstream input(path, std::ios::binary);
  std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
  mbedtls_aes_context context;
  mbedtls_aes_init(&context);
  bool ok = input.good() && output.good() && mbedtls_aes_setkey_dec(&context, key.bytes.data(), 128) == 0;
  auto iv = initial_iv;
  std::array<unsigned char, 64 * 1024> buffer{};
  std::uintmax_t remaining = size;
  while (ok && remaining > 0) {
    if (interrupted()) { ok = false; break; }
    const auto count = static_cast<std::size_t>(std::min<std::uintmax_t>(buffer.size(), remaining));
    input.read(reinterpret_cast<char*>(buffer.data()), static_cast<std::streamsize>(count));
    ok = input.gcount() == static_cast<std::streamsize>(count) &&
      mbedtls_aes_crypt_cbc(&context, MBEDTLS_AES_DECRYPT, count, iv.data(), buffer.data(), buffer.data()) == 0;
    if (!ok) break;
    remaining -= count;
    std::size_t plain_count = count;
    if (remaining == 0) {
      const unsigned char padding = buffer[count - 1];
      if (padding == 0 || padding > 16 ||
          !std::all_of(buffer.begin() + count - padding, buffer.begin() + count,
            [padding](unsigned char byte) { return byte == padding; })) {
        *error = "HLS AES-128 解密填充校验失败，密钥或分片可能已变化。";
        ok = false;
        break;
      }
      plain_count -= padding;
    }
    output.write(reinterpret_cast<const char*>(buffer.data()), static_cast<std::streamsize>(plain_count));
    ok = output.good();
  }
  output.close();
  ok = ok && !output.fail();
  input.close();
  mbedtls_aes_free(&context);
  mbedtls_platform_zeroize(buffer.data(), buffer.size());
  if (ok) {
    std::filesystem::rename(temporary, path, fs_error);
    ok = !fs_error;
  }
  if (!ok) {
    std::filesystem::remove(temporary, fs_error);
    if (error->empty() && !interrupted()) *error = "HLS AES-128 分片解密失败。";
  }
  return ok;
}

}  // namespace aira::download
