/*
 * HLS version of the CA Engine - WORK IN PROGRESS
 *
 * This function implements the Greenberg-Hastings
 * cellular automaton with a 29x29 Moore Neighborhood
 * and 16 states per cell (4-bit cells).
 *
 * The CA Engine accepts a column of the nxn neighborhood
 * and calculates the new value of the central cell based
 * on the CA rule.
 *
 * Control signals like "valid" should remain unchanged
 * in order to preserve compatibility with the rest of
 * the framework.
 *
 * CURRENT IMPLEMENTATION:
 * - Clock 'default' with a period of 5ns and an
 * uncertainty of 0.625ns.
 * - Latency: 29 cycles
 * - Interval: 1 cycle
 * Target device: Artix 7 (xc7a100t-csg324-1)
 * - 9% FF
 * - 37% LUT
 */

#include "ap_int.h" //allows for arbitrary precision data types

#define n 29 //neighborhood size, for example n = 29 for a 29x29 neighborhood
#define threshold 5 //a Greenberg-Hastings parameter

void ca_engine(ap_uint<4> neighborhood_input[n], ap_uint<1> valid_in, ap_uint<4> *output, ap_uint<1> *valid_out){
	#pragma HLS array_partition variable=neighborhood_input complete dim=0 //array as multiple inputs - not loaded sequentially from memory
	#pragma HLS pipeline

	static ap_uint<4> neighborhood[n][n]; //4 bits: up to 16 states per cell
	#pragma HLS array partition variable=neighborhood complete //put all of the values in the array into registers

	static ap_uint<1> valid[n/2+1];
	#pragma HLS array partition variable=valid complete //put all of the values in the array into registers

	ap_uint<5> i, j; //counters for parsing the neighborhood, 5 bits are sufficient for counting 29 elements

	//pipelined neighborhood
	for (i = 0; i < n; i++){
		for (j = n-1; j > 0; j--){
			neighborhood[i][j] = neighborhood[i][j-1];
		}
		neighborhood[i][0] = neighborhood_input[i];
	}

	//accumulate
	ap_uint<5> infected_neighbors_per_row[n]; //5 bits are sufficient for counting 29 elements
	#pragma HLS array partition variable=infected_neighbors_per_row complete //put all of the values in the array into registers

	int infected_neighbors; //ap_uint<10> wouldn't help much here

	//	 The 2 loops below are equivalent to:
	//
	//	infected_neighbors = 0;
	//	for (i = 0; i < n; i++){
	//		for (j = 0; j < n; j++){
	//			if (neighborhood[i][j] == 1){
	//				infected_neighbors++;
	//	 		}
	//		}
	//	}
	//
	//	 The chosen implementation reduces the pipeline depth
	//	 (latency) by taking advantage of the spatial parallelism
	//	 of the algorithm. It has slightly increased demands for
	//	 resources but it probably provides slack for routing.

	for (i = 0; i < n; i++){
		infected_neighbors_per_row[i] = 0;
		for (j = 0; j < n; j++){
			if (neighborhood[i][j] == 1){
				infected_neighbors_per_row[i]++;
			}
		}
	}

	infected_neighbors = 0;
	for (i = 0; i < n; i++){
		infected_neighbors = infected_neighbors + infected_neighbors_per_row[i];
	}

	//excluding current cell
	if (neighborhood[n/2][n/2] == 1){
		infected_neighbors--;
	}

	//transition function
	if ((neighborhood[n/2][n/2] != 0)||(infected_neighbors > threshold)){
		if (neighborhood[n/2][n/2] == 15){
			*output = 0;
		} else {
			*output = neighborhood[n/2][n/2] + 1;
		}
	} else {
		*output = neighborhood[n/2][n/2];
	}

	//valid signal
	for (i = (n/2); i > 0; i--){
		valid[i] = valid[i-1];
	}
	valid[0] = valid_in;

	*valid_out = valid[n/2];
}
