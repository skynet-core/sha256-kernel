/**
This kernel uses last 9 bytes of message, because of
that you must make sure host application assert(data.length <= MSG_SIZE - 9);
Make sure you efficently utilize memory data.length >= MSG_SIZE - BLOCK_SIZE
e.g if MSG_SIZE == 128, pass data with length greater then 64 and less then 120.
 */

#pragma OPENCL EXTENSION cl_khr_global_int32_base_atomics : enable
#define LOCK(a) atom_cmpxchg(a, 0, 1)
#define UNLOCK(a) atom_xchg(a, 0)

#ifndef HASH_WORDS
#define HASH_WORDS 8
#endif
#ifndef BLOCK_SIZE
#define BLOCK_SIZE 64
#endif
#define BLOCK_SIZE 64
#ifndef MSG_SIZE
#define MSG_SIZE BLOCK_SIZE
#endif

#define word unsigned int
#define qword unsigned long

#define SHR(x, n) ((x) >> (n))
#define SHL(x, n) ((x) << (n))
#define ROTLEFT(a, b) (SHL((a), (b)) | SHR((a), (32 - (b))))
#define ROTRIGHT(a, b) (SHR((a), (b)) | SHL((a), (32 - (b))))
#define CHOICE(x, y, z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJOR(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x)                                                                 \
  (ROTRIGHT((x), 2) ^ ROTRIGHT((x), 13) ^ ROTRIGHT((x), 22)) // ~SIG0

#define EP1(x) (ROTRIGHT((x), 6) ^ ROTRIGHT((x), 11) ^ ROTRIGHT((x), 25))
#define SIG0(x) (ROTRIGHT((x), 7) ^ ROTRIGHT((x), 18) ^ ((x) >> 3))
#define SIG1(x) (ROTRIGHT((x), 17) ^ ROTRIGHT((x), 19) ^ ((x) >> 10))

#define _HTONL(x)                                                              \
  ((word)((((word)(x)&0xff000000) >> 24) | (((word)(x)&0x00ff0000) >> 8) |     \
          (((word)(x)&0x0000ff00) << 8) | (((word)(x)&0x000000ff) << 24)))

#define _HTONLL(x)                                                             \
  ((qword)((((qword)(x)&0xff00000000000000) >> 56) |                           \
           (((qword)(x)&0x00ff000000000000) >> 40) |                           \
           (((qword)(x)&0x0000ff0000000000) >> 24) |                           \
           (((qword)(x)&0x000000ff00000000) >> 8) |                            \
           (((qword)(x)&0x00000000ff000000) << 8) |                            \
           (((qword)(x)&0x0000000000ff0000) << 24) |                           \
           (((qword)(x)&0x000000000000ff00) << 40) |                           \
           (((qword)(x)&0x00000000000000ff) << 56)))

#ifdef __ENDIAN_LITTLE__
#define BYTESWAP_L(x) _HTONL(x)
#define BYTESWAP_LL(x) _HTONLL(x)
#else
#define BYTESWAP_L(x) (x)
#define BYTESWAP_LL(x) (x)
#endif

#define print(format, src, size)                                               \
  for (size_t _i = 0; _i < (size_t)(size); _i++) {                             \
    printf(format, (src)[_i]);                                                 \
  }

#define println(format, src, size)                                             \
  print(format, src, size);                                                    \
  printf("\n");

static constant char HEX[16] = {'0', '1', '2', '3', '4', '5', '6', '7',
                                '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};
#define to_hex(src, size, dst)                                                 \
  for (size_t _i = 0; _i < (size_t)(size); _i++) {                             \
    dst[_i * 2] = HEX[(src[_i] >> 4) & 0x0f];                                  \
    dst[_i * 2 + 1] = HEX[src[_i] & 0x0f];                                     \
  }

#define zeros(dst, size)                                                       \
  for (size_t _i = 0; _i < (size_t)(size); _i++) {                             \
    (dst)[_i] = 0;                                                             \
  }

#define _memcpy(dst, src, size)                                                \
  for (size_t _i = 0; _i < (size_t)(size); _i++) {                             \
    (dst)[_i] = (src)[_i];                                                     \
  }

constant word K[BLOCK_SIZE] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

constant word H[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};

#define ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, x)         \
  temp1 = h + EP1(e) + CHOICE(e, f, g) + K[x] + msg_sched[x];                  \
  temp2 = EP0(a) + MAJOR(a, b, c);                                             \
  h = g;                                                                       \
  g = f;                                                                       \
  f = e;                                                                       \
  e = d + temp1;                                                               \
  d = c;                                                                       \
  c = b;                                                                       \
  b = a;                                                                       \
  a = temp1 + temp2;

#define ROUND(hash, msg_sched)                                                 \
  word a = hash[0];                                                            \
  word b = hash[1];                                                            \
  word c = hash[2];                                                            \
  word d = hash[3];                                                            \
  word e = hash[4];                                                            \
  word f = hash[5];                                                            \
  word g = hash[6];                                                            \
  word h = hash[7];                                                            \
  word temp1 = 0;                                                              \
  word temp2 = 0;                                                              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 0)               \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 1)               \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 2)               \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 3)               \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 4)               \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 5)               \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 6)               \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 7)               \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 8)               \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 9)               \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 10)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 11)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 12)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 13)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 14)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 15)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 16)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 17)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 18)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 19)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 20)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 21)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 22)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 23)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 24)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 25)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 26)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 27)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 28)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 29)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 30)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 31)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 32)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 33)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 34)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 35)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 36)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 37)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 38)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 39)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 40)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 41)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 42)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 43)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 44)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 45)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 46)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 47)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 48)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 49)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 50)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 51)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 52)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 53)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 54)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 55)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 56)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 57)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 58)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 59)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 60)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 61)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 62)              \
  ROUND_STEP(msg_sched, a, b, c, d, e, f, g, h, temp1, temp2, 63)              \
  hash[0] += a;                                                                \
  hash[1] += b;                                                                \
  hash[2] += c;                                                                \
  hash[3] += d;                                                                \
  hash[4] += e;                                                                \
  hash[5] += f;                                                                \
  hash[6] += g;                                                                \
  hash[7] += h;

#define BLOCK_SWAP_STEP(array, x) array[x] = BYTESWAP_L(array[x])
#define BLOCK_STEP(array, x)                                                   \
  array[x] =                                                                   \
      SIG1(array[x - 2]) + array[x - 7] + SIG0(array[x - 15]) + array[x - 16]

#define BLOCK_STEP_EXPAND(array)                                               \
  BLOCK_STEP(array, 16);                                                       \
  BLOCK_STEP(array, 17);                                                       \
  BLOCK_STEP(array, 18);                                                       \
  BLOCK_STEP(array, 19);                                                       \
  BLOCK_STEP(array, 20);                                                       \
  BLOCK_STEP(array, 21);                                                       \
  BLOCK_STEP(array, 22);                                                       \
  BLOCK_STEP(array, 23);                                                       \
  BLOCK_STEP(array, 24);                                                       \
  BLOCK_STEP(array, 25);                                                       \
  BLOCK_STEP(array, 26);                                                       \
  BLOCK_STEP(array, 27);                                                       \
  BLOCK_STEP(array, 28);                                                       \
  BLOCK_STEP(array, 29);                                                       \
  BLOCK_STEP(array, 30);                                                       \
  BLOCK_STEP(array, 31);                                                       \
  BLOCK_STEP(array, 32);                                                       \
  BLOCK_STEP(array, 33);                                                       \
  BLOCK_STEP(array, 34);                                                       \
  BLOCK_STEP(array, 35);                                                       \
  BLOCK_STEP(array, 36);                                                       \
  BLOCK_STEP(array, 37);                                                       \
  BLOCK_STEP(array, 38);                                                       \
  BLOCK_STEP(array, 39);                                                       \
  BLOCK_STEP(array, 40);                                                       \
  BLOCK_STEP(array, 41);                                                       \
  BLOCK_STEP(array, 42);                                                       \
  BLOCK_STEP(array, 43);                                                       \
  BLOCK_STEP(array, 44);                                                       \
  BLOCK_STEP(array, 45);                                                       \
  BLOCK_STEP(array, 46);                                                       \
  BLOCK_STEP(array, 47);                                                       \
  BLOCK_STEP(array, 48);                                                       \
  BLOCK_STEP(array, 49);                                                       \
  BLOCK_STEP(array, 50);                                                       \
  BLOCK_STEP(array, 51);                                                       \
  BLOCK_STEP(array, 52);                                                       \
  BLOCK_STEP(array, 53);                                                       \
  BLOCK_STEP(array, 54);                                                       \
  BLOCK_STEP(array, 55);                                                       \
  BLOCK_STEP(array, 56);                                                       \
  BLOCK_STEP(array, 57);                                                       \
  BLOCK_STEP(array, 58);                                                       \
  BLOCK_STEP(array, 59);                                                       \
  BLOCK_STEP(array, 60);                                                       \
  BLOCK_STEP(array, 61);                                                       \
  BLOCK_STEP(array, 62);                                                       \
  BLOCK_STEP(array, 63);

#ifdef __ENDIAN_LITTLE__
#define BLOCK(array)                                                           \
  BLOCK_SWAP_STEP(array, 0);                                                   \
  BLOCK_SWAP_STEP(array, 1);                                                   \
  BLOCK_SWAP_STEP(array, 2);                                                   \
  BLOCK_SWAP_STEP(array, 3);                                                   \
  BLOCK_SWAP_STEP(array, 4);                                                   \
  BLOCK_SWAP_STEP(array, 5);                                                   \
  BLOCK_SWAP_STEP(array, 6);                                                   \
  BLOCK_SWAP_STEP(array, 7);                                                   \
  BLOCK_SWAP_STEP(array, 8);                                                   \
  BLOCK_SWAP_STEP(array, 9);                                                   \
  BLOCK_SWAP_STEP(array, 10);                                                  \
  BLOCK_SWAP_STEP(array, 11);                                                  \
  BLOCK_SWAP_STEP(array, 12);                                                  \
  BLOCK_SWAP_STEP(array, 13);                                                  \
  BLOCK_SWAP_STEP(array, 14);                                                  \
  BLOCK_SWAP_STEP(array, 15);                                                  \
  BLOCK_STEP_EXPAND(array)
#else
#define BLOCK(array) BLOCK_STEP_EXPAND(array)
#endif

#define FILL_PADDING(message, length, n_blocks, msg_tag)                       \
  qword total_bits = BYTESWAP_LL(length * 8);                                  \
  _memcpy((((msg_tag char *)message) + (n_blocks * BLOCK_SIZE) - 8),           \
          ((char *)&total_bits), 8);

#define CALCULATE_STEP(hash, msg_sched, message, msg_tag, i)                   \
  _memcpy(((msg_tag char *)msg_sched),                                         \
          ((msg_tag char *)message) + i * BLOCK_SIZE, BLOCK_SIZE);             \
  BLOCK((msg_sched));                                                          \
  ROUND((hash), (msg_sched));

#if MSG_SIZE == 64
#define CALCULATE(hash, msg_sched, message, length, msg_tag)                   \
  FILL_PADDING(message, length, 1, msg_tag)                                    \
  CALCULATE_STEP(hash, msg_sched, message, msg_tag, 0)
#elif MSG_SIZE == 128
#define CALCULATE(hash, msg_sched, message, length, msg_tag)                   \
  FILL_PADDING(message, length, 2, msg_tag)                                    \
  CALCULATE_STEP(hash, msg_sched, message, msg_tag, 0)                         \
  CALCULATE_STEP(hash, msg_sched, message, msg_tag, 1)
#else
#define CALCULATE(hash, msg_sched, message, length, msg_tag)                   \
  word n_blocks = (length + 72) / BLOCK_SIZE;                                  \
  FILL_PADDING(message, length, n_blocks, msg_tag)                             \
  for (size_t i = 0; i < n_blocks; i++) {                                      \
    CALCULATE_STEP(hash, msg_sched, message, n_blocks, msg_tag, i);
}
#endif

typedef struct ibuff_s {
  word length;
  word message[MSG_SIZE];
  word msg_sched[BLOCK_SIZE];
} inbuff_t;

typedef struct outbuff_s {
  word hash[HASH_WORDS];
} outbuff_t;

#define def_hash(name, msg_tag, hash_tag)                                      \
  void name(msg_tag word *message, msg_tag word *msg_sched, word length,       \
            hash_tag word *hash) {                                             \
    hash[0] = H[0];                                                            \
    hash[1] = H[1];                                                            \
    hash[2] = H[2];                                                            \
    hash[3] = H[3];                                                            \
    hash[4] = H[4];                                                            \
    hash[5] = H[5];                                                            \
    hash[6] = H[6];                                                            \
    hash[7] = H[7];                                                            \
    ((msg_tag char *)message)[length] = 0x80;                                  \
    CALCULATE(hash, msg_sched, message, length, msg_tag);                      \
  }

def_hash(hash_gg, __global, __global);

__kernel void sha256(__global inbuff_t *input, __global outbuff_t *output) {
  unsigned int id = get_global_id(0);
  hash_gg(input[id].message, input[id].msg_sched, input[id].length,
          output[id].hash);
}