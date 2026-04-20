// Tiled GEMM with shared memory, tile size = 8
// C = A * B, all matrices are N x N

#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime.h>

#define N    1024
#define TILE 8

__global__ void gemm_tiled(const float* A, const float* B, float* C, int n) {
    __shared__ float sA[TILE][TILE];
    __shared__ float sB[TILE][TILE];

    int row = blockIdx.y * TILE + threadIdx.y;
    int col = blockIdx.x * TILE + threadIdx.x;
    float sum = 0.0f;

    for (int t = 0; t < (n + TILE - 1) / TILE; t++) {
        int aCol = t * TILE + threadIdx.x;
        int bRow = t * TILE + threadIdx.y;

        sA[threadIdx.y][threadIdx.x] = (row < n && aCol < n) ? A[row * n + aCol] : 0.0f;
        sB[threadIdx.y][threadIdx.x] = (bRow < n && col < n) ? B[bRow * n + col] : 0.0f;

        __syncthreads();

        #pragma unroll
        for (int k = 0; k < TILE; k++)
            sum += sA[threadIdx.y][k] * sB[k][threadIdx.x];

        __syncthreads();
    }

    if (row < n && col < n)
        C[row * n + col] = sum;
}

void init_matrix(float* mat, int n) {
    for (int i = 0; i < n * n; i++)
        mat[i] = (float)(rand() % 10) / 10.0f;
}

int main() {
    size_t bytes = (size_t)N * N * sizeof(float);

    float *h_A = (float*)malloc(bytes);
    float *h_B = (float*)malloc(bytes);
    float *h_C = (float*)malloc(bytes);

    init_matrix(h_A, N);
    init_matrix(h_B, N);

    float *d_A, *d_B, *d_C;
    cudaMalloc(&d_A, bytes);
    cudaMalloc(&d_B, bytes);
    cudaMalloc(&d_C, bytes);

    cudaMemcpy(d_A, h_A, bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(d_B, h_B, bytes, cudaMemcpyHostToDevice);

    dim3 block(TILE, TILE);
    dim3 grid((N + TILE - 1) / TILE, (N + TILE - 1) / TILE);

    // Warm-up
    gemm_tiled<<<grid, block>>>(d_A, d_B, d_C, N);
    cudaDeviceSynchronize();

    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    int runs = 5;
    cudaEventRecord(start);
    for (int i = 0; i < runs; i++)
        gemm_tiled<<<grid, block>>>(d_A, d_B, d_C, N);
    cudaEventRecord(stop);
    cudaEventSynchronize(stop);

    float ms = 0.0f;
    cudaEventElapsedTime(&ms, start, stop);
    ms /= runs;

    double flops = 2.0 * (double)N * N * N;
    double gflops = flops / (ms * 1e-3) / 1e9;

    printf("Kernel: gemm_tiled (tile=%d)\n", TILE);
    printf("Matrix size: %d x %d\n", N, N);
    printf("Avg time: %.3f ms\n", ms);
    printf("Achieved: %.2f GFLOP/s\n", gflops);

    cudaMemcpy(h_C, d_C, bytes, cudaMemcpyDeviceToHost);

    cudaEventDestroy(start);
    cudaEventDestroy(stop);
    free(h_A); free(h_B); free(h_C);
    cudaFree(d_A); cudaFree(d_B); cudaFree(d_C);
    return 0;
}
