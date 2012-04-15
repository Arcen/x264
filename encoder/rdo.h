int x264_rd_cost_mb( x264_t *h, int i_lambda2 );
uint64_t x264_rd_cost_chroma( x264_t *h, int i_lambda2, int i_mode, int b_dct );
uint64_t x264_rd_cost_i4x4( x264_t *h, int i_lambda2, int i4, int i_mode );
uint64_t x264_rd_cost_i8x8( x264_t *h, int i_lambda2, int i8, int i_mode, pixel edge[4][32] );
int ssd_mb( x264_t *h );
