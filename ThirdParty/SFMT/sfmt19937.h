/** 
 * @file sfmt19937.h 
 *
 * @brief SIMD oriented Fast Mersenne Twister(SFMT) pseudorandom
 * number generator
 *
 * @author Mutsuo Saito (Hiroshima University)
 * @author Makoto Matsumoto (Hiroshima University)
 *
 * @date 2007-01-10
 *
 * Copyright (C) 2006, 2007 Mutsuo Saito, Makoto Matsumoto and Hiroshima
 * University. All rights reserved.
 *
 * The new BSD License is applied to this software.
 * see LICENSE.txt
 *
 * @note We assume that your system has inttypes.h.  If your system
 * doesn't have inttypes.h, you have to typedef uint32_t and uint64_t,
 * and you have to define PRIu64 and PRIx64 in this file like this:
 * @verbatim
 typedef unsigned int uint32_t
 typedef unsigned long long uint64_t  
 #define PRIu64 "llu"
 #define PRIx64 "llx"
@endverbatim
 * uint32_t must be exactly 32-bit unsigned integer type (no more, no
 * less), and uint64_t must be exactly 64-bit unsigned integer type.
 * PRIu64 and PRIx64 are used for printf function to print 64-bit
 * unsigned int and 64-bit unsigned int in hexadecimal format.
 */

#ifndef SFMT19937_H
#define SFMT19937_H

#include <stdio.h>

#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L)
  #include <inttypes.h>
#elif defined(_MSC_VER)
  typedef unsigned int uint32_t;
  typedef unsigned long long uint64_t;
  #define inline
#else
  #include <inttypes.h>
  #if defined(__GNUC__)
    #define inline __inline__
  #else
    #define inline
  #endif
#endif

#ifndef PRIu64
  #if defined(_MSC_VER)
    #define PRIu64 "I64u"
    #define PRIx64 "I64x"
  #else
    #define PRIu64 "llu"
    #define PRIx64 "llx"
  #endif
#endif

inline uint32_t gen_rand32(void);
inline uint64_t gen_rand64(void);
inline void fill_array32(uint32_t array[], int size);
inline void fill_array64(uint64_t array[], int size);
void init_gen_rand(uint32_t seed);
void init_by_array(uint32_t init_key[], int key_length);

/* These real versions are due to Isaku Wada */
/** generates a random number on [0,1]-real-interval */
inline static double to_real1(uint32_t v)
{
    return v * (1.0/4294967295.0); 
    /* divided by 2^32-1 */ 
}

/** generates a random number on [0,1]-real-interval */
inline static double genrand_real1(void)
{
    return to_real1(gen_rand32());
}

/** generates a random number on [0,1)-real-interval */
inline static double to_real2(uint32_t v)
{
    return v * (1.0/4294967296.0); 
    /* divided by 2^32 */
}

/** generates a random number on [0,1)-real-interval */
inline static double genrand_real2(void)
{
    return to_real2(gen_rand32());
}

/** generates a random number on (0,1)-real-interval */
inline static double to_real3(uint32_t v)
{
    return (((double)v) + 0.5)*(1.0/4294967296.0); 
    /* divided by 2^32 */
}

/** generates a random number on (0,1)-real-interval */
inline static double genrand_real3(void)
{
    return to_real3(gen_rand32());
}
/** These real versions are due to Isaku Wada */

/** generates a random number on [0,1) with 53-bit resolution*/
inline static double to_res53(uint64_t v) 
{ 
    return v * (1.0/18446744073709551616.0L);
}

/** generates a random number on [0,1) with 53-bit resolution*/
inline static double genrand_res53(void) 
{ 
    return to_res53(gen_rand64());
} 
#endif
