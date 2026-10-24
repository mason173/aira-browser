#include "download_core.h"

#include <chrono>
#include <iostream>
#include <thread>

int main(int argc, char** argv) {
  if (argc < 3) {
    std::cerr << "usage: download_host_test url target [http|hls] [header ...]\n";
    return 2;
  }
  aira::download::TaskOptions options;
  options.url = argv[1];
  options.target_path = argv[2];
  options.hls = argc > 3 && std::string(argv[3]) == "hls";
  for (int index = 4; index < argc; ++index) options.headers.emplace_back(argv[index]);
  aira::download::DownloadTask task(options);
  if (!task.Start()) return 2;
  aira::download::TaskSnapshot snapshot;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);
  while (std::chrono::steady_clock::now() < deadline) {
    snapshot = task.Snapshot();
    if (snapshot.state == aira::download::TaskState::kCompleted ||
        snapshot.state == aira::download::TaskState::kFailed ||
        snapshot.state == aira::download::TaskState::kCanceled) break;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  std::cout << aira::download::TaskStateName(snapshot.state)
            << " code=" << snapshot.error_code << " phase=" << snapshot.failure_phase
            << " message=" << snapshot.error_message << " diagnostic=" << snapshot.diagnostic_message << '\n';
  return snapshot.state == aira::download::TaskState::kCompleted ? 0 : 1;
}
