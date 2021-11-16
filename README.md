# SHA256 OpenCL Kernel

### Notes

* message schedule relies only on each 64-bytes block, so should not be re-used in next steps
* hash sum itself is accumulated for each block
* we can calculate partial hash sum for first N-1 64-bytes blocks, then add block N and calculate final hash

### TODO:

[ ] use int8 vector for hash
[ ] partial hash kernel
