module swap::utils {
    // use std::debug;
    use swap::math;

    const EParamInvalid: u64 = 1;
    public fun get_amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64,
        fee_numerator: u64,
        fee_denumerator: u64
    ): u64 {
        assert!(amount_out > 0, EParamInvalid);
        assert!(reserve_in > 0 && reserve_out > 0, EParamInvalid);
        assert!(fee_numerator > 0 && fee_denumerator > 0, EParamInvalid);
        assert!(fee_denumerator > fee_numerator, EParamInvalid);
        assert!(reserve_out > amount_out, EParamInvalid);

        let denominator = (reserve_out - amount_out) * (fee_denumerator - fee_numerator);
        math::mul_div(amount_out * fee_denumerator, reserve_in, denominator) + 1
    }

    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        fee_numerator: u64,
        fee_denumerator: u64
    ): u64 {
        assert!(amount_in > 0, EParamInvalid);
        assert!(reserve_in > 0 && reserve_out > 0, EParamInvalid);
        assert!(fee_numerator > 0 && fee_denumerator > 0, EParamInvalid);
        assert!(fee_denumerator > fee_numerator, EParamInvalid);

        let amount_in_with_fee = amount_in * (fee_denumerator - fee_numerator);
        let denominator = reserve_in * fee_denumerator + amount_in_with_fee;
        math::mul_div(amount_in_with_fee, reserve_out, denominator)
    }

    public fun quote(amount_a: u64, reserve_a: u64, reserve_b: u64): u64 {
        assert!(amount_a > 0, EParamInvalid);
        assert!(reserve_a > 0 && reserve_b > 0, EParamInvalid);
        math::mul_div(amount_a, reserve_b, reserve_a)
    }

}