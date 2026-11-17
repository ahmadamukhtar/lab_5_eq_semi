// AXI4-Lite UVC: shared types and helpers (included by axi4l_pkg.sv)

parameter int AXI4L_ADDR_W = `AXI4L_ADDR_W;
parameter int AXI4L_DATA_W = `AXI4L_DATA_W;

typedef virtual axi4_lite_if #(.ADDR_WIDTH(AXI4L_ADDR_W),
                               .DATA_WIDTH(AXI4L_DATA_W)) axi4l_vif_t;

typedef logic [AXI4L_ADDR_W-1:0] axi4l_addr_t;
typedef logic [AXI4L_DATA_W-1:0] axi4l_data_t;

typedef enum bit [1:0] {
    AXI4L_RESP_OKAY   = 2'b00,
    AXI4L_RESP_EXOKAY = 2'b01,
    AXI4L_RESP_SLVERR = 2'b10,
    AXI4L_RESP_DECERR = 2'b11
} axi4l_resp_e;

typedef enum {AXI4L_WRITE, AXI4L_READ} axi4l_kind_e;

typedef enum {AXI4L_MASTER, AXI4L_SLAVE} axi4l_mode_e;

// Relative start of AW and W for a write (realised through the item delays).
typedef enum {
    AXI4L_ORDER_AW_FIRST,
    AXI4L_ORDER_W_FIRST,
    AXI4L_ORDER_SAME
} axi4l_wr_order_e;

typedef enum {
    AXI4L_EV_AW,
    AXI4L_EV_W,
    AXI4L_EV_B,
    AXI4L_EV_AR,
    AXI4L_EV_R,
    AXI4L_EV_RST_ASSERT,
    AXI4L_EV_RST_RELEASE
} axi4l_event_e;

// Inclusive delay range in clock cycles.
typedef struct {
    int unsigned min;
    int unsigned max;
} axi4l_dly_t;

function automatic int unsigned axi4l_rand_dly(axi4l_dly_t d);
    return $urandom_range(d.max, d.min);
endfunction

function automatic axi4l_data_t axi4l_rand_data();
    bit [127:0] v;
    v = {$urandom, $urandom, $urandom, $urandom};
    return axi4l_data_t'(v);
endfunction

function automatic axi4l_addr_t axi4l_rand_addr();
    bit [127:0] v;
    v = {$urandom, $urandom, $urandom, $urandom};
    return axi4l_addr_t'(v);
endfunction
