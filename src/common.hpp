#ifndef __MINEX_COMMON_H
#define __MINEX_COMMON_H

#include <sstream>

#ifndef NO_STD
#ifndef CL_HPP_MINIMUM_OPENCL_VERSION
#define CL_HPP_MINIMUM_OPENCL_VERSION 120
#endif

#ifndef CL_HPP_TARGET_OPENCL_VERSION
#define CL_HPP_TARGET_OPENCL_VERSION 120
#endif

#ifndef CL_HPP_ENABLE_EXCEPTIONS
#define CL_HPP_ENABLE_EXCEPTIONS 1
#endif

#ifndef CL_HPP_ENABLE_PROGRAM_CONSTRUCTION_FROM_ARRAY_COMPATIBILITY
#define CL_HPP_ENABLE_PROGRAM_CONSTRUCTION_FROM_ARRAY_COMPATIBILITY 1
#endif
#endif

#include <CL/opencl.hpp>

#define WORD cl_uint
#define QWORD cl_ulong
#define BLOCK_SIZE 64
#define WORD_SIZE sizeof(WORD)
#define QWORD_SIZE sizeof(QWORD)
#define MSG_SIZE BLOCK_SIZE
#define DEFAULT_CL_BUILD_OPTIONS "-Werror -DBLOCK_SIZE=64 -DMSG_SIZE=64"

#define MAX_MSG_SIZE BLOCK_SIZE *WORD_SIZE - QWORD_SIZE

typedef struct inbuff_s {
  WORD length;
  WORD message[MSG_SIZE];
  WORD msg_sched[BLOCK_SIZE];
} inbuff_t;

typedef struct outbuff_s {
  WORD hash[8];
} outbuff_t;

std::string get_build_log(const cl::BuildError &e) {
  auto build_logs = e.getBuildLog();
  std::stringstream ss;
  ss << e.what() << ": ";
  for (auto &&bl : build_logs) {
    ss << "\n\t" << bl.first.getInfo<CL_DEVICE_NAME>() << ": " << bl.second;
  }
  return ss.str();
}

#endif