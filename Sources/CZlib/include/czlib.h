#ifndef CZLIB_H
#define CZLIB_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Raw DEFLATE decompression (RFC 1951).
 *
 * `src` must contain a raw deflate stream (no zlib/gzip wrapper).
 * On success 0 is returned and `*out_len` holds the number of bytes written.
 * On failure a negative zlib error code is returned.
 */
int cz_inflate(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_cap, size_t *out_len);

/* zlib-wrapped DEFLATE (RFC 1950) — used by some archive formats. */
int cz_uncompress_zlib(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_cap, size_t *out_len);

/* zlib-wrapped DEFLATE compression (RFC 1950). */
int cz_compress_zlib(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_cap, size_t *out_len);

/* CRC-32 (IEEE) of a buffer. */
uint32_t cz_crc32(const uint8_t *data, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* CZLIB_H */
