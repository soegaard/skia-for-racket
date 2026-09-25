/* Host-C mirror of SkiaSharp 3.119.1's include/c/sk_types.h.
   This checks our mirrored layout, not the actual installed native library. */
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

typedef struct {
    int16_t zone_minutes;
    uint16_t year;
    uint8_t month, weekday, day, hour, minute, second;
} pdf_datetime;

typedef struct {
    void *title, *author, *subject, *keywords, *creator, *producer;
    pdf_datetime *creation, *modified;
    float raster_dpi;
    bool pdfa;
    int quality;
} pdf_metadata;

_Static_assert(sizeof(pdf_datetime) == 10, "PDF timestamp size");
_Static_assert(offsetof(pdf_datetime, year) == 2, "PDF year offset");
_Static_assert(offsetof(pdf_datetime, month) == 4, "PDF month offset");
_Static_assert(offsetof(pdf_datetime, second) == 9, "PDF second offset");
_Static_assert(sizeof(int) == 4 && sizeof(float) == 4 && sizeof(bool) == 1,
               "PDF scalar ABI");
_Static_assert(offsetof(pdf_metadata, creation) == 6 * sizeof(void *), "creation offset");
_Static_assert(offsetof(pdf_metadata, raster_dpi) == 8 * sizeof(void *), "DPI offset");
_Static_assert(offsetof(pdf_metadata, pdfa) == 8 * sizeof(void *) + 4, "bool offset");
_Static_assert(offsetof(pdf_metadata, quality) == 8 * sizeof(void *) + 8, "quality offset");
_Static_assert(sizeof(pdf_metadata) == (sizeof(void *) == 8 ? 80 : 44), "metadata size");

int main(void) {
    printf("PDF ABI mirror passed: metadata=%zu timestamp=%zu pointer=%zu\n",
           sizeof(pdf_metadata), sizeof(pdf_datetime), sizeof(void *));
    return 0;
}
