#ifndef SOGOOD_FFI_H
#define SOGOOD_FFI_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t *data;
    size_t len;
    size_t capacity;
} SogoodBuffer;

#endif /* SOGOOD_FFI_H */
