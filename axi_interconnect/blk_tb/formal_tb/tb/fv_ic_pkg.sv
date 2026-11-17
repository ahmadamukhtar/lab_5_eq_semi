// Formal-only package: address-map reference for the default interconnect map.
// Nine 4 KiB windows from 0x0, lowest window wins on overlap. Returns the
// subordinate index 0..8, or 4'hF for a decode miss.

package fv_ic_pkg;
    function automatic logic [3:0] fv_dec(input logic [63:0] a);
        for (int i = 0; i < 9; i++)
            if ((a & ~64'hFFF) == (64'(i) * 64'h1000))
                return 4'(i);
        return 4'hF;
    endfunction
endpackage
