#include <stdio.h>
#include <strings.h>
#include "sfmt19937.h"

int main(int argc, char* argv[]) {
    int i, cnt, seed_cnt;
    double x, y, pi;
    const int NUM = 10000;
    uint32_t seeds[100];

    if (argc >= 2) {
	seed_cnt = 0;
	for (i = 0; (i < 100) && (i < strlen(argv[1])); i++) {
	    seeds[i] = argv[1][i];
	    seed_cnt++;
	}
    } else {
	seeds[0] = 12345;
	seed_cnt = 1;
    }
    cnt = 0;
    init_by_array(seeds, seed_cnt);
    for (i = 0; i < NUM; i++) {
	x = genrand_res53();
	y = genrand_res53();
	if (x * x + y * y < 1.0) {
	    cnt++;
	}
    }
    pi = (double)cnt / NUM * 4;
    printf("%lf\n", pi);
    return 0;
}
