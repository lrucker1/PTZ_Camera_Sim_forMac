#include "jr_hex_print.h"
#include <stdio.h>

void hex_print(char *buf, int buf_size) {
    for (int i = 0; i < buf_size; i++) {
        printf("%02hhx ", buf[i]);
    }
}