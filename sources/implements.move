module swap::implements {
    use sui::clock::{Clock};
    use std::ascii::into_bytes;
    use std::string::{Self, String};
    use std::type_name::{get, into_string};
    use std::vector;

    use sui::object::{Self, ID, UID};
    use sui::balance::{Self, Supply, Balance};
    use sui::bag::{Self, Bag};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{Self};
    use sui::coin::{Self, Coin};
    use sui::event;

    use swap::comparator;
    use swap::math;
    use swap::utils;

    friend swap::interface;

    /// events
    struct SetFeeEvent has copy, drop {
        sender: address,
        pool_id: ID,
        fee_numerator: u64,
        fee_denominator: u64,
    }

    struct SwapEvent has copy, drop {
        lp_name: String,
        amount_x_in: u64,
        amount_y_in: u64,
        amount_x_out: u64,
        amount_y_out: u64,
    }

    struct MintEvent has copy, drop {
        lp_name: String,
        amount_x: u64,
        amount_y: u64,
        liquidity: u64
    }

    #[test_only]
    friend swap::tests;

    /// For when Coin is zero.
    const ERR_ZERO_AMOUNT: u64 = 0;
    /// For when someone tries to swap in an empty pool.
    const ERR_RESERVES_EMPTY: u64 = 1;
    /// For when someone attempts to add more liquidity than u128 Math allows.
    const ERR_POOL_FULL: u64 = 2;
    /// Insuficient amount in coin x reserves.
    const ERR_INSUFFICIENT_COIN_X: u64 = 3;
    /// Insuficient amount in coin y reserves.
    const ERR_INSUFFICIENT_COIN_Y: u64 = 4;
    /// Divide by zero while calling mul_div.
    const ERR_DIVIDE_BY_ZERO: u64 = 5;
    /// For when someone add liquidity with invalid parameters.
    const ERR_OVERLIMIT: u64 = 6;
    /// Amount out less than minimum.
    const ERR_COIN_OUT_NUM_LESS_THAN_EXPECTED_MINIMUM: u64 = 7;
    /// Liquid not enough.
    const ERR_LIQUID_NOT_ENOUGH: u64 = 8;
    /// Coin X is the same as Coin Y
    const ERR_THE_SAME_COIN: u64 = 9;
    /// Pool X-Y has registered
    const ERR_POOL_HAS_REGISTERED: u64 = 10;
    /// Pool X-Y not register
    const ERR_POOL_NOT_REGISTER: u64 = 11;
    /// Coin X and Coin Y order
    const ERR_MUST_BE_ORDER: u64 = 12;
    /// Overflow for u64
    const ERR_U64_OVERFLOW: u64 = 13;
    /// Incorrect swap
    const ERR_INCORRECT_SWAP: u64 = 14;
    /// Insufficient liquidity
    const ERR_INSUFFICIENT_LIQUIDITY_MINTED: u64 = 15;

    const ECoinInsufficient: u64 = 15;

    const ESwapoutCalcInvalid: u64 = 16;

    const ELiquidityInsufficientMinted: u64 = 17;

    const ELiquiditySwapBurnCalcInvalid: u64 = 18;

    const EPoolInvalid: u64 = 19;

    const EAMOUNTINCORRECT: u64 = 20;

    const ERR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 21;

    const ERR_INSUFFICIENT_INPUT_AMOUNT:u64 = 22;

    const ENotEnough: u64 = 22;

    const EWrongFee: u64 = 23;

    const ERR_INPUT_VALUE: u64 = 24;

    const MINIMAL_LIQUIDITY: u64 = 1000;

    const U64_MAX: u64 = 18446744073709551615;

    const MAX_POOL_VALUE: u64 = {
        18446744073709551615 / 10000
    };

    /// The Pool token that will be used to mark the pool share
    /// of a liquidity provider. The parameter `X` and `Y` is for the
    /// coin held in the pool.
    struct LP<phantom X, phantom Y> has drop, store {}

    /// The pool with exchange.
    struct Pool<phantom X, phantom Y> has store {
        global: ID,
        coin_x: Balance<X>,
        coin_y: Balance<Y>,
        lp_supply: Supply<LP<X, Y>>,
        min_liquidity: Balance<LP<X, Y>>,
        fee_numerator: u64,
        fee_denominator: u64,
    }

    /// The global config
    struct Global has key {
        id: UID,
        pools: Bag,
    }

    /// Init global config
    fun init(ctx: &mut TxContext) {
        let global = Global {
            id: object::new(ctx),
            pools: bag::new(ctx)
        };

        transfer::share_object(global)
    }
    
    public fun global_id<X, Y>(pool: &Pool<X, Y>): ID {
        pool.global
    }

    public(friend) fun id<X, Y>(global: &Global): ID {
        object::uid_to_inner(&global.id)
    }

    public(friend) fun get_mut_pool<X, Y>(
        global: &mut Global,
        is_order: bool,
    ): &mut Pool<X, Y> {
        assert!(is_order, ERR_MUST_BE_ORDER);

        let lp_name = generate_lp_name<X, Y>();
        let has_registered = bag::contains_with_type<String, Pool<X, Y>>(&global.pools, lp_name);
        assert!(has_registered, ERR_POOL_NOT_REGISTER);

        bag::borrow_mut<String, Pool<X, Y>>(&mut global.pools, lp_name)
    }

    public(friend) fun has_registered<X, Y>(
        global: &Global
    ): bool {
        let lp_name = generate_lp_name<X, Y>();
        bag::contains_with_type<String, Pool<X, Y>>(&global.pools, lp_name)
    }

    public fun generate_lp_name<X, Y>(): String {
        let lp_name = string::utf8(b"");
        string::append_utf8(&mut lp_name, b"LP-");

        if (is_order<X, Y>()) {
            string::append_utf8(&mut lp_name, into_bytes(into_string(get<X>())));
            string::append_utf8(&mut lp_name, b"-");
            string::append_utf8(&mut lp_name, into_bytes(into_string(get<Y>())));
        } else {
            string::append_utf8(&mut lp_name, into_bytes(into_string(get<Y>())));
            string::append_utf8(&mut lp_name, b"-");
            string::append_utf8(&mut lp_name, into_bytes(into_string(get<X>())));
        };

        lp_name
    }

    public fun is_order<X, Y>(): bool {
        let comp = comparator::compare(&get<X>(), &get<Y>());
        assert!(!comparator::is_equal(&comp), ERR_THE_SAME_COIN);

        if (comparator::is_smaller_than(&comp)) {
            true
        } else {
            false
        }
    }

    /// Register pool
    public(friend) fun register_pool<X, Y>(
        global: &mut Global,
        is_order: bool
    ) {
        assert!(is_order, ERR_MUST_BE_ORDER);

        let lp_name = generate_lp_name<X, Y>();
        let has_registered = bag::contains_with_type<String, Pool<X, Y>>(&global.pools, lp_name);
        assert!(!has_registered, ERR_POOL_HAS_REGISTERED);

        let lp_supply = balance::create_supply(LP<X, Y>{});
        let new_pool = Pool {
            global: object::uid_to_inner(&global.id),
            coin_x: balance::zero<X>(),
            coin_y: balance::zero<Y>(),
            lp_supply,
            min_liquidity: balance::zero<LP<X, Y>>(),
            fee_numerator: 0,
            fee_denominator: 0,
        };
        bag::add(&mut global.pools, lp_name, new_pool);
    }

    /// Add liquidity to the `Pool`. Sender needs to provide both
    /// `Coin<X>` and `Coin<Y>`, and in exchange he gets `Coin<LP>` -
    /// liquidity provider tokens.
    public(friend) fun add_liquidity<X, Y>(
        pool: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        coin_x_min: u64,
        coin_y: Coin<Y>,
        coin_y_min: u64,
        is_order: bool,
        ctx: &mut TxContext
    ): (Coin<LP<X, Y>>, vector<u64>) {
        assert!(is_order, ERR_MUST_BE_ORDER);

        let coin_x_value = coin::value(&coin_x);
        let coin_y_value = coin::value(&coin_y);

        assert!(coin_x_value > 0 && coin_y_value > 0, ERR_ZERO_AMOUNT);

        let coin_x_balance = coin::into_balance(coin_x);
        let coin_y_balance = coin::into_balance(coin_y);

        let (coin_x_reserve, coin_y_reserve, lp_supply) = get_reserves_size(pool);
        let (optimal_coin_x, optimal_coin_y) = calc_optimal_coin_values(
            coin_x_value, coin_y_value,
            coin_x_min, coin_y_min,
            coin_x_reserve, coin_y_reserve
        );

        let provided_liq = if (0 == lp_supply) {
            let initial_liq = math::sqrt(math::mul_to_u128(optimal_coin_x, optimal_coin_y));
            assert!(initial_liq > MINIMAL_LIQUIDITY, ERR_LIQUID_NOT_ENOUGH);

            let minimal_liquidity = balance::increase_supply(
                &mut pool.lp_supply,
                MINIMAL_LIQUIDITY
            );
            balance::join(&mut pool.min_liquidity, minimal_liquidity);

            initial_liq - MINIMAL_LIQUIDITY
        } else {
            let x_liq = (lp_supply as u128) * (optimal_coin_x as u128) / (coin_x_reserve as u128);
            let y_liq = (lp_supply as u128) * (optimal_coin_y as u128) / (coin_y_reserve as u128);
            if (x_liq < y_liq) {
                assert!(x_liq < (U64_MAX as u128), ERR_U64_OVERFLOW);
                (x_liq as u64)
            } else {
                assert!(y_liq < (U64_MAX as u128), ERR_U64_OVERFLOW);
                (y_liq as u64)
            }
        };

        assert!(provided_liq > 0, ERR_INSUFFICIENT_LIQUIDITY_MINTED);

        if (optimal_coin_x < coin_x_value) {
            transfer::public_transfer(
                coin::from_balance(balance::split(&mut coin_x_balance, coin_x_value - optimal_coin_x), ctx),
                tx_context::sender(ctx)
            )
        };
        if (optimal_coin_y < coin_y_value) {
            transfer::public_transfer(
                coin::from_balance(balance::split(&mut coin_y_balance, coin_y_value - optimal_coin_y), ctx),
                tx_context::sender(ctx)
            )
        };

        let coin_x_amount = balance::join(&mut pool.coin_x, coin_x_balance);
        let coin_y_amount = balance::join(&mut pool.coin_y, coin_y_balance);

        assert!(coin_x_amount < MAX_POOL_VALUE, ERR_POOL_FULL);
        assert!(coin_y_amount < MAX_POOL_VALUE, ERR_POOL_FULL);

        let balance = balance::increase_supply(&mut pool.lp_supply, provided_liq);

        let return_values = vector::empty<u64>();
        vector::push_back(&mut return_values, coin_x_value);
        vector::push_back(&mut return_values, coin_y_value);
        vector::push_back(&mut return_values, provided_liq);

        (coin::from_balance(balance, ctx), return_values)
    }

    /// Remove liquidity from the `Pool` by burning `Coin<LP>`.
    /// Returns `Coin<X>` and `Coin<Y>`.
    public(friend) fun remove_liquidity<X, Y>(
        pool: &mut Pool<X, Y>,
        lp_coin: Coin<LP<X, Y>>,
        is_order: bool,
        ctx: &mut TxContext,
    ): (Coin<X>, Coin<Y>) {
        assert!(is_order, ERR_MUST_BE_ORDER);

        let lp_val = coin::value(&lp_coin);
        assert!(lp_val > 0, ERR_ZERO_AMOUNT);

        let (coin_x_amount, coin_y_amount, lp_supply) = get_reserves_size(pool);
        let coin_x_out = math::mul_div(coin_x_amount, lp_val, lp_supply);
        let coin_y_out = math::mul_div(coin_y_amount, lp_val, lp_supply);

        balance::decrease_supply(&mut pool.lp_supply, coin::into_balance(lp_coin));
        (
            coin::take(&mut pool.coin_x, coin_x_out, ctx),
            coin::take(&mut pool.coin_y, coin_y_out, ctx)
        )
    }

    /// Get most used values in a handy way:
    /// - amount of Coin<X>
    /// - amount of Coin<Y>
    /// - total supply of LP<X,Y>
    public fun get_reserves_size<X, Y>(pool: &Pool<X, Y>): (u64, u64, u64) {
        (
            balance::value(&pool.coin_x),
            balance::value(&pool.coin_y),
            balance::supply_value(&pool.lp_supply)
        )
    }


    /// burn lp
    /// require X < Y
    public fun burn<X, Y>(
        pool: &mut Pool<X, Y>,
        _: &Clock,
        liquidity: Balance<LP<X, Y>>
    ): (Balance<X>, Balance<Y>) {
        // feeOn

        let liquidity_amount = balance::value(&liquidity);
        let (reserve_x, reserve_y, _) = get_reserves_size(pool);
        let total_supply = balance::supply_value<LP<X, Y>>(&pool.lp_supply);
        let amount_x = ((liquidity_amount as u128) * (reserve_x as u128) / (total_supply as u128) as u64);
        let amount_y = ((liquidity_amount as u128) * (reserve_y as u128) / (total_supply as u128) as u64);
        let x_coin_to_return = balance::split(&mut pool.coin_x, amount_x);
        let y_coin_to_return = balance::split(&mut pool.coin_y, amount_y);
        balance::decrease_supply(&mut pool.lp_supply, liquidity);

        // event
        let lp_name = generate_lp_name<X, Y>();
        event::emit(MintEvent {
            lp_name,
            amount_x,
            amount_y,
            liquidity: liquidity_amount,
        });
        (x_coin_to_return, y_coin_to_return)
    }

    /// Calculate amounts needed for adding new liquidity for both `X` and `Y`.
    /// Returns both `X` and `Y` coins amounts.
    public fun calc_optimal_coin_values(
        coin_x_desired: u64,
        coin_y_desired: u64,
        coin_x_min: u64,
        coin_y_min: u64,
        coin_x_reserve: u64,
        coin_y_reserve: u64
    ): (u64, u64) {
        if (coin_x_reserve == 0 && coin_y_reserve ==0) {
            return (coin_x_desired, coin_y_desired)
        } else {
            let coin_y_returned = math::mul_div(coin_x_desired, coin_y_reserve, coin_x_reserve);
            if (coin_y_returned <= coin_y_desired) {
                assert!(coin_y_returned >= coin_y_min, ERR_INSUFFICIENT_COIN_Y);
                return (coin_x_desired, coin_y_returned)
            } else {
                let coin_x_returned = math::mul_div(coin_y_desired, coin_x_reserve, coin_y_reserve);
                assert!(coin_x_returned <= coin_x_desired, ERR_OVERLIMIT);
                assert!(coin_x_returned >= coin_x_min, ERR_INSUFFICIENT_COIN_X);
                return (coin_x_returned, coin_y_desired)
            }
        }
    }

    public fun return_remaining_coin<X>(
        coin: Coin<X>,
        ctx: &mut TxContext,
    ) {
        if (coin::value(&coin) == 0) {
            coin::destroy_zero(coin);
        } else {
            transfer::public_transfer(coin, tx_context::sender(ctx));
        };
    }

    public fun get_swap_fee<X, Y>(pool: &Pool<X, Y>) : (u64, u64) {
        (pool.fee_numerator, pool.fee_denominator)
    }

    /// Set swap fees
    /// Requires X < Y
    public(friend) fun set_swap_fee<X, Y>(
        pool: &mut Pool<X, Y>,
        fee_numerator: u64,
        fee_denominator: u64,
        ctx: &mut TxContext,
    ) {
        pool.fee_numerator = fee_numerator;
        pool.fee_denominator = fee_denominator;

        event::emit(SetFeeEvent{
            sender: tx_context::sender(ctx),
            pool_id: pool.global,
            fee_numerator,
            fee_denominator,
        });
    }

    /// swap from Coin to Coin, both sides
    /// Requires X < Y
    public fun swap_coins_for_coins<X, Y>(
        pool: &mut Pool<X, Y>,
        clock: &Clock,
        coins_x_in: Coin<X>,
        coins_y_in: Coin<Y>,
        ctx: &mut TxContext,
    ): (Coin<X>, Coin<Y>) {
        let (balance_x_out, balance_y_out)=
            swap_balance_for_balance<X, Y>(pool, clock, coin::into_balance<X>(coins_x_in), coin::into_balance<Y>(coins_y_in));
        (coin::from_balance<X>(balance_x_out, ctx), coin::from_balance<Y>(balance_y_out, ctx))
    }

    /// swap from Balance to Balance, both sides
    /// Requires X < Y
    public fun swap_balance_for_balance<X, Y>(
        pool: &mut Pool<X, Y>,
        clock: &Clock,
        coins_x_in: Balance<X>,
        coins_y_in: Balance<Y>,
    ): (Balance<X>, Balance<Y>) {
        let amount_x_in = balance::value(&coins_x_in);
        let amount_y_in = balance::value(&coins_y_in);
        assert!((amount_x_in > 0 && amount_y_in == 0) || (amount_x_in == 0 || amount_x_in > 0), ERR_INPUT_VALUE);
        let (fee_numerator, fee_denominator) = get_swap_fee(pool);
        if (amount_x_in > 0) {
            let (reserve_in, reserve_out, _) = get_reserves_size<X, Y>(pool);
            let amount_out = utils::get_amount_out(amount_x_in, reserve_in, reserve_out, fee_numerator, fee_denominator);
            swap<X, Y>(pool, clock, coins_x_in, 0, coins_y_in, amount_out)
        } else {
            let (reserve_out, reserve_in, _) = get_reserves_size<X, Y>(pool);
            let amount_out = utils::get_amount_out(amount_y_in, reserve_in, reserve_out, fee_numerator, fee_denominator);
            swap<X, Y>(pool, clock, coins_x_in, amount_out, coins_y_in, 0)
        }
    }

    /// Swap coins, both sides
    /// require X < Y
    public fun swap<X, Y>(
        pool: &mut Pool<X, Y>,
        _: &Clock,
        coins_x_in: Balance<X>,
        amount_x_out: u64,
        coins_y_in: Balance<Y>,
        amount_y_out: u64,
    ): (Balance<X>, Balance<Y>) {
        let amount_x_in = balance::value(&coins_x_in);
        let amount_y_in = balance::value(&coins_y_in);
        assert!(amount_x_in > 0 || amount_y_in > 0, ERR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(amount_x_out > 0 || amount_y_out > 0, ERR_INSUFFICIENT_OUTPUT_AMOUNT);
        balance::join<X>(&mut pool.coin_x, coins_x_in);
        balance::join<Y>(&mut pool.coin_y, coins_y_in);
        let coins_x_out = balance::split(&mut pool.coin_x, amount_x_out);
        let coins_y_out = balance::split(&mut pool.coin_y, amount_y_out);
        
        let lp_name = generate_lp_name<X, Y>();
        // event
        event::emit(SwapEvent {
            lp_name,
            amount_x_in,
            amount_y_in,
            amount_x_out,
            amount_y_out,
        });
        (coins_x_out, coins_y_out)
    }

    /// X in and Y out
    /// Requires X < Y
    public(friend) fun get_amounts_in<X, Y>(
        pool:&mut Pool<X, Y>,
        amount_out: u64,
    ): u64 {
        let (reserve_in, reserve_out, _) = get_reserves_size<X, Y>(pool);
        let (fee_numerator, fee_denominator) = get_swap_fee(pool);
        utils::get_amount_in(amount_out, reserve_in, reserve_out, fee_numerator, fee_denominator)        
    }

    /// X in and Y out
    /// Requires X < Y
    public(friend) fun get_amounts_out<X, Y>(
        pool:&mut Pool<X, Y>,
        amount_in: u64,
    ): u64 {
        let (reserve_in, reserve_out, _) = get_reserves_size<X, Y>(pool);
        let (fee_numerator, fee_denominator) = get_swap_fee(pool);
        utils::get_amount_out(amount_in, reserve_in, reserve_out, fee_numerator, fee_denominator)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}