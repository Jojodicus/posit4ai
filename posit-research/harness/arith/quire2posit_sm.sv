// Parameterised Quire-to-Posit converter for posit(POSLEN, es=2).
// Purely combinatorial -- the caller registers posit_o.
//
// Algorithm mirrors PERCIVAL's Quire2Posit / PositFastEncoder (pau_q2p.vhd),
// re-implemented in SV for arbitrary POSLEN (designed/tested for 8 and 16).
//
// Quire bit layout  (Q = 16*POSLEN, MAXEXP = 4*(POSLEN-2)):
//   quire[Q-1]                          = sign
//   quire[Q-2 : MAXEXP+POSRANGE_W]      = carryBits   (CARRY_W = 4*POSLEN+22 bits)
//   quire[MAXEXP+POSRANGE_W-1 : MAXEXP] = positRange  (POSRANGE_W = 8*(POSLEN-2)+1 bits)
//   quire[MAXEXP-1 : 0]                 = stickyRange (MAXEXP bits)

module quire2posit_sm #(
  parameter int POSLEN = 16   // posit width; es=2 is fixed
) (
  input  logic [16*POSLEN-1:0]  quire_i,
  output logic [POSLEN-1:0]     posit_o   // combinatorial
);

  // -- Derived constants ---------------------------------------
  localparam int Q          = 16 * POSLEN;
  localparam int MAXEXP     = 4 * (POSLEN - 2);         // = log2(maxpos)
  localparam int POSRANGE_W = 8 * (POSLEN - 2) + 1;    // significant range bits
  localparam int CARRY_W    = 4 * POSLEN + 22;          // overflow guard width
  localparam int FRAC_W     = POSLEN - 5;               // fraction bits (es=2 posit)
  // LZOC count: ceil(log2(POSRANGE_W+1)) bits
  localparam int LZOC_W     = $clog2(POSRANGE_W + 1);
  // Scaling factor: MSB = rc, bits [SF_W-2:2] = k, bits [1:0] = exp (es=2)
  localparam int SF_W       = $clog2(MAXEXP + 1) + 2;
  // Regime value (magnitude of k, clipped to POSLEN-2)
  localparam int REGV_W     = $clog2(POSLEN - 1);

  // -- Quire slice extraction -----------------------------------
  logic                     sgn;
  logic [CARRY_W-1:0]       carryBits;
  logic [POSRANGE_W-1:0]    positRange;
  logic [MAXEXP-1:0]        stickyRange;

  assign sgn         = quire_i[Q-1];
  assign carryBits   = quire_i[Q-2 : MAXEXP+POSRANGE_W];
  assign positRange  = quire_i[MAXEXP+POSRANGE_W-1 : MAXEXP];
  assign stickyRange = quire_i[MAXEXP-1 : 0];

  // -- Overflow and underflow ---------------------------------
  logic carryAllZeros, carryAllOnes, ovf, stkTmp;

  assign carryAllZeros = (carryBits == '0);
  assign carryAllOnes  = (&carryBits);
  // Overflow: carry has non-sign polarity bits (same as PERCIVAL check)
  assign ovf    = sgn ? carryAllZeros : carryAllOnes;
  assign stkTmp = (stickyRange != '0);

  // ---- LZOC: count leading zeros (sgn=0) or ones (sgn=1) in positRange --------------------
  // Result is LZOC_W bits; maximum possible count = POSRANGE_W.
  logic [LZOC_W-1:0]     intExp;
  logic [POSRANGE_W-1:0] tmpFrac;

  // ---- LZOC: generate-based priority encoder ------------------------------------------------------------------------
  // lzoc_in[i] = 1 when positRange bit (POSRANGE_W-1-i) differs from sgn; i=0 = MSB
  logic [POSRANGE_W-1:0] lzoc_in;
  generate
    for (genvar gi = 0; gi < POSRANGE_W; gi++) begin : g_lzoc_in
      assign lzoc_in[gi] = positRange[POSRANGE_W-1-gi] ^ sgn;
    end
  endgenerate

  // Priority encode: intExp = index of first '1' in lzoc_in, or POSRANGE_W if all '0'.
  // No break -> unrolled to a parallel priority mux tree by synthesis.
  always_comb begin : lzoc_enc
    intExp = LZOC_W'(POSRANGE_W);
    for (int i = POSRANGE_W-1; i >= 0; i--)
      if (lzoc_in[i]) intExp = LZOC_W'(i);
  end

  // Left barrel shifter: tmpFrac = positRange << intExp  (LZOC_W log2-stages)
  logic [POSRANGE_W-1:0] lbs [LZOC_W+1];
  assign lbs[0] = positRange;
  generate
    for (genvar s = 0; s < LZOC_W; s++) begin : g_lbs
      localparam int LDIST = 1 << s;
      if (LDIST < POSRANGE_W) begin : g_lbs_narrow
        assign lbs[s+1] = intExp[s] ? {lbs[s][POSRANGE_W-1-LDIST:0], {LDIST{1'b0}}} : lbs[s];
      end else begin : g_lbs_wide
        assign lbs[s+1] = intExp[s] ? {POSRANGE_W{1'b0}} : lbs[s];
      end
    end
  endgenerate
  assign tmpFrac = lbs[LZOC_W];

  // ---- Zero / NaR detection ----------------------------------------------------------------------------------------------------------
  logic intExpZero, intExpMax, positZero, nzn;

  assign intExpZero = (intExp == '0);
  assign intExpMax  = (intExp == LZOC_W'(POSRANGE_W));
  // positZero: positive result at zero, or negative at NaR boundary
  assign positZero  = sgn ? intExpZero : intExpMax;
  assign nzn        = ~carryAllZeros | ~positZero | stkTmp;

  // ---- Fraction, guard, sticky extraction from normalised mantissa ------------------------------
  // tmpFrac[POSRANGE_W-1] is the hidden 1; fraction follows immediately.
  logic [FRAC_W-1:0] frac;
  logic              grd, stkBit, stk;

  assign frac   = tmpFrac[POSRANGE_W-2 : POSRANGE_W-2-FRAC_W+1];
  assign grd    = tmpFrac[POSRANGE_W-2-FRAC_W];
  assign stkBit = (tmpFrac[POSRANGE_W-3-FRAC_W:0] != '0);
  assign stk    = stkBit | stkTmp;

  // ---- Scaling factor sf = MAXEXP - intExp (clip to MAXEXP on overflow) --------------------
  // sf[SF_W-1] = rc (regime direction), sf[SF_W-2:2] = k field, sf[1:0] = exp
  logic signed [SF_W-1:0] sf;

  always_comb begin : sf_compute
    automatic logic signed [SF_W-1:0] sfTmp;
    sfTmp = SF_W'(signed'(MAXEXP)) - SF_W'(signed'(intExp));
    sf    = ovf ? SF_W'(signed'(MAXEXP)) : sfTmp;
  end

  // ---- Posit encoder (mirrors PositFastEncoder from pau_q2p.vhd) ----------------------------------
  localparam int K_W = SF_W - 3;   // width of k field = SF_W - 1 (MSB) - 2 (es bits)

  logic               rc, regNeg, padBit, regOvf;
  logic [K_W-1:0]     k_raw;
  logic [1:0]         exp_field;
  logic [REGV_W-1:0]  regValue;

  assign rc        = sf[SF_W-1];
  // k = regime count magnitude: XOR upper sf bits with rc to extract absolute value
  assign k_raw     = sf[SF_W-2:2] ^ {K_W{rc}};
  assign exp_field = sf[1:0] ^ {2{sgn}};
  // Clip regime to maximum (POSLEN-2) as in PERCIVAL PositFastEncoder
  assign regOvf    = (k_raw > K_W'(POSLEN - 2));
  assign regValue  = regOvf ? REGV_W'(POSLEN - 2) : k_raw[REGV_W-1:0];

  assign regNeg = sgn ^ rc;
  assign padBit = ~regNeg;

  // ---- Right-shift-with-sticky (regime generator) ----------------------------------------------------------------
  // inputShifter = {regNeg, exp[1:0], frac[FRAC_W-1:0], grd} = POSLEN-1 bits
  logic [POSLEN-2:0] inputShifter, shiftedPosit;
  logic              stkBit2;

  assign inputShifter = {regNeg, exp_field, frac, grd};

  // ---- Right barrel shifter with sticky (regime generator) ----------------------------------------------
  // Shifts inputShifter right by regValue, fills from left with padBit,
  // and OR-reduces all shifted-out bits into stkBit2.  REGV_W log2-stages.
  logic [POSLEN-2:0]    rbs     [REGV_W+1];
  logic [REGV_W-1:0]    rbs_stk;
  assign rbs[0] = inputShifter;
  generate
    for (genvar s = 0; s < REGV_W; s++) begin : g_rbs
      localparam int RDIST = 1 << s;
      if (RDIST < POSLEN-1) begin : g_rbs_narrow
        assign rbs_stk[s] = regValue[s] ? |rbs[s][RDIST-1:0] : 1'b0;
        assign rbs[s+1]   = regValue[s] ? {{RDIST{padBit}}, rbs[s][POSLEN-2:RDIST]} : rbs[s];
      end else begin : g_rbs_wide
        assign rbs_stk[s] = regValue[s] ? |rbs[s] : 1'b0;
        assign rbs[s+1]   = regValue[s] ? {(POSLEN-1){padBit}} : rbs[s];
      end
    end
  endgenerate
  assign shiftedPosit = rbs[REGV_W];
  assign stkBit2      = |rbs_stk;

  // ---- Round to nearest even ----------------------------------------------------------------------------------------------------------
  logic [POSLEN-2:0] unroundedPosit, roundedPosit;
  logic              lsb, rnd_bit, stk_all, do_round;

  assign unroundedPosit = {padBit, shiftedPosit[POSLEN-2:1]};
  assign lsb            = shiftedPosit[1];
  assign rnd_bit        = shiftedPosit[0];
  assign stk_all        = stkBit2 | stk;
  assign do_round       = rnd_bit & (lsb | stk_all | regOvf);
  assign roundedPosit   = unroundedPosit + (POSLEN-1)'(do_round);

  // ---- Final output ----------------------------------------------------------------------------------------------------------------------------
  logic [POSLEN-2:0] unsignedPosit;
  assign unsignedPosit = nzn ? roundedPosit : '0;
  assign posit_o       = {sgn, unsignedPosit};

endmodule
