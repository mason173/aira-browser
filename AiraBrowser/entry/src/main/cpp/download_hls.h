#ifndef AIRA_DOWNLOAD_HLS_H
#define AIRA_DOWNLOAD_HLS_H

#include <array>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace aira::download {

struct HlsKey {
  std::string url;
  std::array<unsigned char, 16> bytes{};
  ~HlsKey();
};

// Initialization sections are entries in the same ordered plan as media. This
// keeps MAP changes, byte ranges and encryption bound to the segment they affect.
struct HlsResource {
  std::string url;
  std::int64_t offset = -1;
  std::int64_t length = 0;
  int key_index = -1;
  std::array<unsigned char, 16> iv{};
  bool initialization = false;
};

struct HlsVariant {
  std::int64_t bandwidth = 0;
  std::string url;
  std::string audio_group;
  bool external_audio = false;
};

struct HlsPlan {
  std::vector<HlsResource> resources;
  std::vector<HlsKey> keys;
  std::uint64_t hash = 0;
  bool fragmented_mp4 = false;
};

// Presentation only: estimates never participate in transfer integrity checks.
// The owning DownloadTask serializes access with its snapshot mutex.
class HlsProgressTracker {
 public:
  explicit HlsProgressTracker(const std::vector<HlsResource>& resources);
  void Update(std::size_t index, std::int64_t received, std::int64_t total);
  void Complete(std::size_t index, std::int64_t bytes);
  double Fraction() const;
  std::int64_t EstimatedTotalBytes() const;

 private:
  struct ResourceProgress {
    bool initialization = false;
    bool completed = false;
    double fraction = 0;
  };
  std::vector<ResourceProgress> resources_;
  double completed_units_ = 0;
  std::size_t media_count_ = 0;
  std::size_t map_count_ = 0;
  std::size_t completed_media_count_ = 0;
  std::size_t completed_map_count_ = 0;
  double media_bytes_ = 0;
  double map_bytes_ = 0;
};

bool ParseHlsMedia(const std::string& playlist, const std::string& base_url,
                   HlsPlan* plan, std::vector<HlsVariant>* variants, std::string* error);
bool DecryptHlsFile(const std::string& path, const HlsKey& key,
                    const std::array<unsigned char, 16>& iv,
                    const std::function<bool()>& interrupted, std::string* error);

}  // namespace aira::download
#endif
