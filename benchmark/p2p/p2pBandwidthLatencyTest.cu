/*
 * =====================================================================================
 *
 *       Filename:  p2pBandwidthLatencyTest.cu
 *
 *    Description:  This microbenchmark is to obtain the latency & uni/bi-directional
 *                  bandwidth for PCI-e, NVLink-V1 in NVIDIA P100 DGX-1 and NVLink-V2 in 
 *                  V100 DGX-1. Please see our IISWC-18 paper titled "Tartan: Evaluating 
 *                  Modern GPU Interconnects via a Multi-GPU Benchmark Suite". The
 *                  Code is modified from the p2pBandwidthLatencyTest app in 
 *                  NVIDIA CUDA-SDK. Please follow NVIDIA's EULA for end usage. 
 *
 *        Version:  1.0
 *        Created:  01/24/2018 02:12:31 PM
 *       Revision:  none
 *       Compiler:  nvcc
 *
 *         Author:  Ang Li, PNNL
 *        Website:  http://www.angliphd.com  
 *
 * =====================================================================================
 */

/*
 * Copyright 1993-2015 NVIDIA Corporation.  All rights reserved.
 *
 * Please refer to the NVIDIA end user license agreement (EULA) associated
 * with this source code for terms and conditions that govern your use of
 * this software. Any use, reproduction, disclosure, or distribution of
 * this software and related documentation outside the terms of the EULA
 * is strictly prohibited.
 *
 */

#define ASCENDING

#include <cstdio>
#include <vector>

using namespace std;

const char *sSampleName = "P2P (Peer-to-Peer) GPU Bandwidth Latency Test";

//Macro for checking cuda errors following a cuda launch or api call
#define cudaCheckError() {                                          \
        cudaError_t e=cudaGetLastError();                                 \
        if(e!=cudaSuccess) {                                              \
            printf("Cuda failure %s:%d: '%s'\n",__FILE__,__LINE__,cudaGetErrorString(e));           \
            exit(EXIT_SUCCESS);                                           \
        }                                                                 \
    }
__global__ void delay(int * null) {
  float j=threadIdx.x;
  for(int i=1;i<10000;i++)
      j=(j+1)/j;

  if(threadIdx.x == j) null[0] = j;
}

void checkP2Paccess(int numGPUs)
{
    for (int i=0; i<numGPUs; i++)
    {
        cudaSetDevice(i);

        for (int j=0; j<numGPUs; j++)
        {
            int access;
            if (i!=j)
            {
                cudaDeviceCanAccessPeer(&access,i,j);
                printf("Device=%d %s Access Peer Device=%d\n", i, access ? "CAN" : "CANNOT", j);
            }
        }
    }
    printf("\n***NOTE: In case a device doesn't have P2P access to other one, it falls back to normal memcopy procedure.\nSo you can see lesser Bandwidth (GB/s) in those cases.\n\n");
}

void outputBandwidthMatrix(int numGPUs, bool p2p)
{
    int numElems=10000000;
    int repeat=5;
    vector<int *> buffers(numGPUs);
    vector<cudaEvent_t> start(numGPUs);
    vector<cudaEvent_t> stop(numGPUs);

    for (int d=0; d<numGPUs; d++)
    {
        cudaSetDevice(d);
        cudaMalloc(&buffers[d],numElems*sizeof(int));
        cudaCheckError();
        cudaEventCreate(&start[d]);
        cudaCheckError();
        cudaEventCreate(&stop[d]);
        cudaCheckError();
    }

    vector<double> bandwidthMatrix(numGPUs*numGPUs);

    for (int i=0; i<numGPUs; i++)
    {
        cudaSetDevice(i);

        for (int j=0; j<numGPUs; j++)
        {
            int access;
            bool routingrequired = false;
            int routingnode = -1;

            if(p2p) {
                cudaDeviceCanAccessPeer(&access,i,j);
                if (access)
                {
                    cudaDeviceEnablePeerAccess(j,0 );
                    cudaCheckError();
                }
                else if (i != j) //not local communication
                {
                    routingrequired = true;
                    int src2route, route2dst;
#ifdef ASCENDING
                    for (int k=0; k<numGPUs; k++)
#else
                    for (int k=numGPUs-1; k>=0; k--)
#endif
                    {
                        cudaDeviceCanAccessPeer(&src2route,i,k);
                        cudaDeviceCanAccessPeer(&route2dst,k,j);
                        if (src2route && route2dst)
                        {
                            routingnode =  k;
                            break;
                        }
                    }
                    cudaDeviceEnablePeerAccess(routingnode,0 );
                    cudaCheckError();
                    cudaSetDevice(routingnode);
                    cudaDeviceEnablePeerAccess(j,0 );
                    cudaSetDevice(i);
                }
            }

            cudaDeviceSynchronize();
            cudaCheckError();

            if (routingrequired)
            {
                delay<<<1,1>>>(NULL);
                cudaEventRecord(start[i]);
                for (int r=0; r<repeat; r++)
                {
                    cudaMemcpyPeerAsync(buffers[i],i,buffers[routingnode],routingnode,sizeof(int)*numElems);
                    //cudaSetDevice(routingnode);

                    cudaMemcpyPeerAsync(buffers[routingnode],routingnode,buffers[j],j,sizeof(int)*numElems);
                    //cudaSetDevice(i);
                }

                cudaEventRecord(stop[i]);
                cudaDeviceSynchronize();
                cudaCheckError();
            }
            else
            {
                delay<<<1,1>>>(NULL);
                cudaEventRecord(start[i]);

                for (int r=0; r<repeat; r++)
                {
                    cudaMemcpyPeerAsync(buffers[i],i,buffers[j],j,sizeof(int)*numElems);
                }

                cudaEventRecord(stop[i]);
                cudaDeviceSynchronize();
                cudaCheckError();
            }

            float time_ms;
            cudaEventElapsedTime(&time_ms,start[i],stop[i]);
            double time_s=time_ms/1e3;

            double gb=numElems*sizeof(int)*repeat/(double)1e9;
            if(i==j) gb*=2;  //must count both the read and the write here
            bandwidthMatrix[i*numGPUs+j]=gb/time_s;
            if (p2p)
            {
                if (access)
                {
                    cudaDeviceDisablePeerAccess(j);
                    cudaCheckError();
                }
                
                if (routingrequired)
                {
                    cudaDeviceDisablePeerAccess(routingnode);
                    cudaCheckError();
                    cudaSetDevice(routingnode);
                    cudaDeviceDisablePeerAccess(j);
                    cudaCheckError();
                    cudaSetDevice(i);
                }
            }
        }
    }

    printf("   D\\D");

    for (int j=0; j<numGPUs; j++)
    {
        printf("%6d ", j);
    }

    printf("\n");

    for (int i=0; i<numGPUs; i++)
    {
        printf("%6d ",i);

        for (int j=0; j<numGPUs; j++)
        {
            printf("%6.02f ", bandwidthMatrix[i*numGPUs+j]);
        }

        printf("\n");
    }

    for (int d=0; d<numGPUs; d++)
    {
        cudaSetDevice(d);
        cudaFree(buffers[d]);
        cudaCheckError();
        cudaEventDestroy(start[d]);
        cudaCheckError();
        cudaEventDestroy(stop[d]);
        cudaCheckError();
    }
}

void outputBidirectionalBandwidthMatrix(int numGPUs, bool p2p)
{
    int numElems=10000000;
    int repeat=5;
    vector<int *> buffers(numGPUs);
    vector<cudaEvent_t> start(numGPUs);
    vector<cudaEvent_t> stop(numGPUs);
    vector<cudaStream_t> stream0(numGPUs);
    vector<cudaStream_t> stream1(numGPUs);

    for (int d=0; d<numGPUs; d++)
    {
        cudaSetDevice(d);
        cudaMalloc(&buffers[d],numElems*sizeof(int));
        cudaCheckError();
        cudaEventCreate(&start[d]);
        cudaCheckError();
        cudaEventCreate(&stop[d]);
        cudaCheckError();
        cudaStreamCreate(&stream0[d]);
        cudaCheckError();
        cudaStreamCreate(&stream1[d]);
        cudaCheckError();
    }

    vector<double> bandwidthMatrix(numGPUs*numGPUs);

    for (int i=0; i<numGPUs; i++)
    {
        cudaSetDevice(i);

        for (int j=0; j<numGPUs; j++)
        {
            int access;
            bool routingrequired = false;
            int routingnode = -1;

            if(p2p) {
                cudaDeviceCanAccessPeer(&access,i,j);
                if (access)
                {
                    cudaSetDevice(i);
                    cudaDeviceEnablePeerAccess(j,0);
                    cudaCheckError();
                    cudaSetDevice(j);
                    cudaDeviceEnablePeerAccess(i,0);
                    cudaCheckError();
                    cudaSetDevice(i);
                }
                else if (i != j) // not the local communication
                {
                    routingrequired = true;
                    int src2route, route2dst;

#ifdef ASCENDING
                    for (int k=0; k<numGPUs; k++)
#else
                    for (int k=numGPUs-1; k>=0; k--)
#endif
                    {
                        cudaDeviceCanAccessPeer(&src2route,i,k);
                        cudaDeviceCanAccessPeer(&route2dst,k,j);
                        if (src2route && route2dst)
                        {
                            routingnode =  k;
                            break;
                        }
                    }
                    cudaSetDevice(i);
                    cudaDeviceEnablePeerAccess(routingnode,0 );
                    cudaCheckError();
                    cudaSetDevice(routingnode);
                    cudaDeviceEnablePeerAccess(i,0 );
                    cudaCheckError();
                    cudaDeviceEnablePeerAccess(j,0 );
                    cudaCheckError();
                    cudaSetDevice(j);
                    cudaDeviceEnablePeerAccess(routingnode,0 );
                    cudaSetDevice(i);
                    cudaCheckError();
                }
            }

            cudaSetDevice(i);
            cudaDeviceSynchronize();
            cudaCheckError();

            if (routingrequired)
            {
                delay<<<1,1>>>(NULL);
                cudaEventRecord(start[i]);
                for (int r=0; r<repeat; r++)
                {
                    cudaMemcpyPeerAsync(buffers[i],i,buffers[routingnode],routingnode,sizeof(int)*numElems,stream0[i]);
                    cudaMemcpyPeerAsync(buffers[j],j,buffers[routingnode],routingnode,sizeof(int)*numElems,stream0[i]);
                    cudaMemcpyPeerAsync(buffers[routingnode],routingnode,buffers[j],j,sizeof(int)*numElems,stream0[i]);
                    cudaMemcpyPeerAsync(buffers[routingnode],routingnode,buffers[i],i,sizeof(int)*numElems,stream0[i]);
                }

                cudaEventRecord(stop[i]);
                cudaDeviceSynchronize();
                cudaCheckError();

            }
            else
            {
                delay<<<1,1>>>(NULL);
                cudaEventRecord(start[i]);

                for (int r=0; r<repeat; r++)
                {
                    cudaMemcpyPeerAsync(buffers[i],i,buffers[j],j,sizeof(int)*numElems,stream0[i]);
                    cudaMemcpyPeerAsync(buffers[j],j,buffers[i],i,sizeof(int)*numElems,stream1[i]);
                }

                cudaEventRecord(stop[i]);
                cudaDeviceSynchronize();
                cudaCheckError();
            }




            float time_ms;
            cudaEventElapsedTime(&time_ms,start[i],stop[i]);
            double time_s=time_ms/1e3;

            double gb=2.0*numElems*sizeof(int)*repeat/(double)1e9;
            if(i==j) gb*=2;  //must count both the read and the write here
            bandwidthMatrix[i*numGPUs+j]=gb/time_s;
            if(p2p)
            {
                if (access)
                {
                    cudaSetDevice(i);
                    cudaDeviceDisablePeerAccess(j);
                    cudaSetDevice(j);
                    cudaDeviceDisablePeerAccess(i);
                }
                
                if (routingrequired)
                {
                    cudaSetDevice(i);
                    cudaDeviceDisablePeerAccess(routingnode);
                    cudaSetDevice(routingnode);
                    cudaDeviceDisablePeerAccess(i);
                    cudaDeviceDisablePeerAccess(j);
                    cudaSetDevice(j);
                    cudaDeviceDisablePeerAccess(routingnode);
                    cudaSetDevice(i);
                }
            }
        }
    }

    printf("   D\\D");

    for (int j=0; j<numGPUs; j++)
    {
        printf("%6d ", j);
    }

    printf("\n");

    for (int i=0; i<numGPUs; i++)
    {
        printf("%6d ",i);

        for (int j=0; j<numGPUs; j++)
        {
            printf("%6.02f ", bandwidthMatrix[i*numGPUs+j]);
        }

        printf("\n");
    }

    for (int d=0; d<numGPUs; d++)
    {
        cudaSetDevice(d);
        cudaFree(buffers[d]);
        cudaCheckError();
        cudaEventDestroy(start[d]);
        cudaCheckError();
        cudaEventDestroy(stop[d]);
        cudaCheckError();
        cudaStreamDestroy(stream0[d]);
        cudaCheckError();
        cudaStreamDestroy(stream1[d]);
        cudaCheckError();
    }
}

void outputLatencyMatrix(int numGPUs, bool p2p)
{
    int repeat=10000;
    vector<int *> buffers(numGPUs);
    vector<cudaEvent_t> start(numGPUs);
    vector<cudaEvent_t> stop(numGPUs);

    for (int d=0; d<numGPUs; d++)
    {
        cudaSetDevice(d);
        cudaMalloc(&buffers[d],1);
        cudaCheckError();
        cudaEventCreate(&start[d]);
        cudaCheckError();
        cudaEventCreate(&stop[d]);
        cudaCheckError();
    }

    vector<double> latencyMatrix(numGPUs*numGPUs);

    for (int i=0; i<numGPUs; i++)
    {
        cudaSetDevice(i);
        for (int j=0; j<numGPUs; j++)
        {
            int access;
            bool routingrequired = false;
            int routingnode = -1;
            if(p2p) 
            {
                cudaDeviceCanAccessPeer(&access,i,j);
                if (access)
                {
                    cudaDeviceEnablePeerAccess(j,0);
                    cudaCheckError();
                }
                else if (i!=j) //not local communication
                {
                    routingrequired = true;
                    int src2route, route2dst;
#ifdef ASCENDING
                    for (int k=0; k<numGPUs; k++)
#else
                    for (int k=numGPUs-1; k>=0; k--)
#endif
                    {
                        cudaDeviceCanAccessPeer(&src2route,i,k);
                        cudaDeviceCanAccessPeer(&route2dst,k,j);
                        if (src2route && route2dst)
                        {
                            routingnode =  k;
                            break;
                        }
                    }
                    cudaSetDevice(i);
                    cudaDeviceEnablePeerAccess(routingnode,0 );
                    cudaCheckError();
                    cudaSetDevice(routingnode);
                    cudaDeviceEnablePeerAccess(j,0 );
                    cudaCheckError();
                    cudaSetDevice(i);
                }
            }
            cudaDeviceSynchronize();
            cudaCheckError();


            if (routingrequired)
            {
                delay<<<1,1>>>(NULL);
                cudaEventRecord(start[i]);

                for (int r=0; r<repeat; r++)
                {
                    cudaMemcpyPeerAsync(buffers[i],i,buffers[routingnode],routingnode,1);
                    cudaMemcpyPeerAsync(buffers[routingnode],routingnode,buffers[j],j,1);
                }

                cudaEventRecord(stop[i]);
                cudaDeviceSynchronize();
                cudaCheckError();
            }
            else
            {
                delay<<<1,1>>>(NULL);
                cudaEventRecord(start[i]);

                for (int r=0; r<repeat; r++)
                {
                    cudaMemcpyPeerAsync(buffers[i],i,buffers[j],j,1);
                }

                cudaEventRecord(stop[i]);
                cudaDeviceSynchronize();
                cudaCheckError();
            
            }

            float time_ms;
            cudaEventElapsedTime(&time_ms,start[i],stop[i]);

            latencyMatrix[i*numGPUs+j]=time_ms*1e3/repeat;
            if(p2p)
            {
                if (access)
                {
                    cudaDeviceDisablePeerAccess(j);
                    cudaCheckError();
                }
                if (routingrequired)
                {
                    //printf("%d=>%d=>%d,(access:%d,routingrequired:%d\n",i,routingnode,j,access, routingrequired);
                    cudaCheckError();
                    cudaDeviceDisablePeerAccess(routingnode);
                    cudaCheckError();
                    cudaSetDevice(routingnode);
                    cudaDeviceDisablePeerAccess(j);
                    cudaCheckError();
                    cudaSetDevice(i);
                }
            }
        }
    }

    printf("   D\\D");

    for (int j=0; j<numGPUs; j++)
    {
        printf("%6d ", j);
    }

    printf("\n");

    for (int i=0; i<numGPUs; i++)
    {
        printf("%6d ",i);

        for (int j=0; j<numGPUs; j++)
        {
            printf("%6.02f ", latencyMatrix[i*numGPUs+j]);
        }

        printf("\n");
    }

    for (int d=0; d<numGPUs; d++)
    {
        cudaSetDevice(d);
        cudaFree(buffers[d]);
        cudaCheckError();
        cudaEventDestroy(start[d]);
        cudaCheckError();
        cudaEventDestroy(stop[d]);
        cudaCheckError();
    }
}

int main(int argc, char **argv)
{

    int numGPUs;
    cudaGetDeviceCount(&numGPUs);

    printf("[%s]\n", sSampleName);

    //output devices
    for (int i=0; i<numGPUs; i++)
    {
        cudaDeviceProp prop;
        cudaGetDeviceProperties(&prop,i);
        printf("Device: %d, %s, pciBusID: %x, pciDeviceID: %x, pciDomainID:%x\n",i,prop.name, prop.pciBusID, prop.pciDeviceID, prop.pciDomainID);
    }

    checkP2Paccess(numGPUs);

    //Check peer-to-peer connectivity
    printf("P2P Connectivity Matrix\n");
    printf("     D\\D");

    for (int j=0; j<numGPUs; j++)
    {
        printf("%6d", j);
    }
    printf("\n");

    for (int i=0; i<numGPUs; i++)
    {
        printf("%6d\t", i);
        for (int j=0; j<numGPUs; j++)
        {
            if (i!=j)
            {
               int access;
               cudaDeviceCanAccessPeer(&access,i,j);
               printf("%6d", (access) ? 1 : 0);
            }
            else
            {
                printf("%6d", 1);
            }
        }
        printf("\n");
    }

    printf("Unidirectional P2P=Disabled Bandwidth Matrix (GB/s)\n");
    outputBandwidthMatrix(numGPUs, false);
    printf("Unidirectional P2P=Enabled Bandwidth Matrix (GB/s)\n");
    outputBandwidthMatrix(numGPUs, true);
    printf("Bidirectional P2P=Disabled Bandwidth Matrix (GB/s)\n");
    outputBidirectionalBandwidthMatrix(numGPUs, false);
    printf("Bidirectional P2P=Enabled Bandwidth Matrix (GB/s)\n");
    outputBidirectionalBandwidthMatrix(numGPUs, true);


    printf("P2P=Disabled Latency Matrix (us)\n");
    outputLatencyMatrix(numGPUs, false);
    printf("P2P=Enabled Latency Matrix (us)\n");
    outputLatencyMatrix(numGPUs, true);

    printf("\nNOTE: The CUDA Samples are not meant for performance measurements. Results may vary when GPU Boost is enabled.\n");

    exit(EXIT_SUCCESS);
}
