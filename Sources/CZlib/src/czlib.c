#include "czlib.h"

#include <string.h>
#include <zlib.h>

static int cz_run(z_stream *stream, const uint8_t *src, size_t src_len,
                  uint8_t *dst, size_t dst_cap, size_t *out_len) {
    stream->next_in = (Bytef *)src;
    stream->avail_in = (uInt)src_len;
    stream->next_out = (Bytef *)dst;
    stream->avail_out = (uInt)dst_cap;

    int status = inflate(stream, Z_FINISH);
    size_t produced = dst_cap - stream->avail_out;
    if (out_len) {
        *out_len = produced;
    }
    if (status == Z_STREAM_END || status == Z_BUF_ERROR) {
        /* Z_BUF_ERROR is returned when the output buffer is exactly the right size. */
        return 0;
    }
    return status == Z_OK ? -1 : status;
}

int cz_inflate(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_cap, size_t *out_len) {
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    /* Negative window bits select the raw deflate format (no zlib header). */
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
        return -1;
    }
    int result = cz_run(&stream, src, src_len, dst, dst_cap, out_len);
    inflateEnd(&stream);
    return result;
}

int cz_uncompress_zlib(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_cap, size_t *out_len) {
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit(&stream) != Z_OK) {
        return -1;
    }
    int result = cz_run(&stream, src, src_len, dst, dst_cap, out_len);
    inflateEnd(&stream);
    return result;
}

uint32_t cz_crc32(const uint8_t *data, size_t len) {
    return (uint32_t)crc32(crc32(0L, Z_NULL, 0), (const Bytef *)data, (uInt)len);
}

int cz_compress_zlib(const uint8_t *src, size_t src_len, uint8_t *dst, size_t dst_cap, size_t *out_len) {
    uLongf produced = (uLongf)dst_cap;
    int status = compress2((Bytef *)dst, &produced, (const Bytef *)src, (uLong)src_len, Z_DEFAULT_COMPRESSION);
    if (out_len) {
        *out_len = (size_t)produced;
    }
    return status == Z_OK ? 0 : status;
}
