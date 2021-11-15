#include "common.hpp"
#include "error.hpp"
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fmt/chrono.h>
#include <fmt/core.h>
#include <fmt/ranges.h>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <memory>
#include <unordered_map>

int main(int argc, char *argv[]) {
  assert(argc > 1);
  try {
    cl::vector<cl::Device> devices;
    cl::vector<cl::Platform> platforms;
    cl::Platform::get(&platforms);
    platforms[0].getDevices(CL_DEVICE_TYPE_GPU, &devices);

    std::ifstream program_file("lib/sha256.cl");
    std::string program_string(std::istreambuf_iterator<char>(program_file),
                               (std::istreambuf_iterator<char>()));

    cl::Program::Sources source(
        1, std::make_pair(program_string.c_str(), program_string.length() + 1));
    cl::Context context{devices};
    cl::Program program{context, source};

    program.build(DEFAULT_CL_BUILD_OPTIONS);
    for (auto &&dev : devices) {
      auto name = dev.getInfo<CL_DEVICE_NAME>();
      fmt::print("DEVICE_NAME: {}\n", name);
    }

    auto device = devices[0];
    cl::CommandQueue cmd_queue{context, device};
    auto max_work_item_dims =
        device.getInfo<CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS>();
    size_t max_work_group_size =
        device.getInfo<CL_DEVICE_MAX_WORK_GROUP_SIZE>();
    size_t max_work_items = std::pow(max_work_group_size, max_work_item_dims);
    fmt::print("CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS: {}\n", max_work_item_dims);
    fmt::print("CL_DEVICE_MAX_WORK_GROUP_SIZE: {}\n", max_work_group_size);
    fmt::print("CL_DEVICE_WORK_ITEMS: {}\n", max_work_items);
    cl::Kernel worker_kernel{program, "sha256"};
    // std::unordered_map<std::string, std::function<void(void)>> branch_table;
    const char *data = "abc";
    size_t len = strlen(data);
    size_t global_work = max_work_items / max_work_group_size;
    cl::vector<inbuff_t> input{global_work};
    for (auto &&in : input) {
      in.length = len;
      if (in.length > MAX_MSG_SIZE) {
        std::cerr << "ERROR: max overflow input size" << std::endl;
      }
      memcpy(in.message, data, in.length);
    }
    cl::Buffer input_b(context, CL_MEM_READ_WRITE | CL_MEM_USE_HOST_PTR,
                       sizeof(inbuff_t) * input.size(), input.data());
    worker_kernel.setArg(0, input_b);

    cl::vector<outbuff_t> output{global_work};
    cl::Buffer output_b{context, CL_MEM_WRITE_ONLY | CL_MEM_USE_HOST_PTR,
                        sizeof(outbuff_t) * output.size(), output.data()};
    worker_kernel.setArg(1, output_b);

    auto start = std::chrono::system_clock::now();

    fmt::print("kernel started at: {}\n", start);
    size_t amount = max_work_items;
    for (size_t i = 0; i < amount; i += global_work) {
      cmd_queue.enqueueNDRangeKernel(worker_kernel, cl::NDRange{0},
                                     cl::NDRange{global_work}, cl::NDRange{1},
                                     NULL, NULL);
    }
    cmd_queue.finish();
    auto end = std::chrono::system_clock::now();
    auto duration = end.time_since_epoch() - start.time_since_epoch();
    auto took =
        std::chrono::duration_cast<std::chrono::seconds>(duration).count();
    fmt::print("operation took: {}\n", took);
    if (took > 0) {
      for (int i = 0; i < 8; i++) {
        fmt::print("{0:4x}", output[0].hash[i]);
      }
      fmt::print("\n");
      fmt::print("hashrate: {:.2f}Mh/s\n",
                 ((double)(amount * max_work_group_size / took / 1'000'000)));
    }
  } catch (const cl::BuildError &e) {
    std::cerr << get_build_log(e) << std::endl;
    return -1;
  } catch (const cl::Error &e) {
    std::cerr << "ERROR: " << e.err() << " - " << e.what() << '\n';
    return -2;
  } catch (const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -3;
  }
  return 0;
}