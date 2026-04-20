// Naive GEMM: one thread computes one output element C[row][col]
// C = A * B, all matrices are N x N

#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime.h>

#define N 1024

__global__ void gemm_naive(const float* A, const float* B, float* C, int n) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;

    if (row < n && col < n) {
        float sum = 0.0f;
        for (int k = 0; k < n; k++) {
            sum += A[row * n + k] * B[k * n + col];
        }
        C[row * n + col] = sum;
    }
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

    dim3 block(16, 16);
    dim3 grid((N + block.x - 1) / block.x, (N + block.y - 1) / block.y);

    // Warm-up
    gemm_naive<<<grid, block>>>(d_A, d_B, d_C, N);
    cudaDeviceSynchronize();

    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    int runs = 5;
    cudaEventRecord(start);
    for (int i = 0; i < runs; i++)
        gemm_naive<<<grid, block>>>(d_A, d_B, d_C, N);
    cudaEventRecord(stop);
    cudaEventSynchronize(stop);

    float ms = 0.0f;
    cudaEventElapsedTime(&ms, start, stop);
    ms /= runs;

    double flops = 2.0 * (double)N * N * N;
    double gflops = flops / (ms * 1e-3) / 1e9;

    printf("Kernel: gemm_naive\n");
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
