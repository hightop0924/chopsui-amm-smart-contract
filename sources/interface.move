module swap::interface {
    use sui::clock::{Clock};
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use swap::implements::{Self, Global, LP};

    const ERR_NO_PERMISSIONS: u64 = 101;
    const ERR_EMERGENCY: u64 = 102;
    const ERR_GLOBAL_MISMATCH: u64 = 103;
    const ERR_UNEXPECTED_RETURN: u64 = 104;
    const ERR_EMPTY_COINS: u64 = 105;
    const ERR_INSUFFICIENT_INPUT_AMOUNT: u64 = 106;
    const ERR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 107;

    /// Entrypoint for the `add_liquidity` method.
    /// Sends `LP<X,Y>` to the transaction sender.
    public entry fun add_liquidity<X, Y>(
        global: &mut Global,
        coin_x: Coin<X>,
        coin_x_min: u64,
        coin_y: Coin<Y>,
        coin_y_min: u64,
        ctx: &mut TxContext
    ) {
        // assert!(!implements::is_emergency(global), ERR_EMERGENCY);
        let is_order = implements::is_order<X, Y>();

        if (!implements::has_registered<X, Y>(global)) {
            implements::register_pool<X, Y>(global, is_order)
        };
        let pool = implements::get_mut_pool<X, Y>(global, is_order);

        let (lp, return_values) = implements::add_liquidity(
            pool,
            coin_x, 
            coin_x_min,
            coin_y,
            coin_y_min,
            is_order,
            ctx
        );
        assert!(vector::length(&return_values) == 3, ERR_UNEXPECTED_RETURN);

        transfer::public_transfer(
            lp,
            tx_context::sender(ctx)
        );

        // let lp_name = implements::generate_lp_name<X, Y>();

        // added_event(
        //     global,
        //     lp_name,
        //     coin_x_val,
        //     coin_y_val,
        //     lp_val
        // )
    }

    /// Entrypoint for the `remove_liquidity` method.
    /// Transfers Coin<X> and Coin<Y> to the sender.
    public entry fun remove_liquidity<X, Y>(
        global: &mut Global,
        lp_coin: Coin<LP<X, Y>>,
        ctx: &mut TxContext
    ) {
        // assert!(!implements::is_emergency(global), ERR_EMERGENCY);
        let is_order = implements::is_order<X, Y>();
        let pool = implements::get_mut_pool<X, Y>(global, is_order);

        // let lp_val = value(&lp_coin);
        let (coin_x, coin_y) = implements::remove_liquidity(pool, lp_coin, is_order, ctx);
        // let coin_x_val = value(&coin_x);
        // let coin_y_val = value(&coin_y);

        transfer::public_transfer(
            coin_x,
            tx_context::sender(ctx)
        );

        transfer::public_transfer(
            coin_y,
            tx_context::sender(ctx)
        );

        // let global = implements::global_id<X, Y>(pool);
        // let lp_name = implements::generate_lp_name<X, Y>();

        // removed_event(
        //     global,
        //     lp_name,
        //     coin_x_val,
        //     coin_y_val,
        //     lp_val
        // )

    }

    public entry fun set_swap_fee<X, Y>(
        global: &mut Global,
        fee_numerator: u64,
        fee_denominator: u64,
        ctx: &mut TxContext
    ) {
        let is_order = implements::is_order<X, Y>();

        if (implements::has_registered<X, Y>(global)) {

            let pool = implements::get_mut_pool<X, Y>(global, is_order);

            implements::set_swap_fee<X, Y>(pool, fee_numerator, fee_denominator, ctx);
        }
    }

    public entry fun swap_exact_coinA_for_coinB<X, Y>(
        global: &mut Global,
        clock: &Clock,
        coins_in_origin: Coin<X>,
        amount_in: u64,
        amount_out_min: u64,
        ctx: &mut TxContext,
    ) {
        let is_order = implements::is_order<X, Y>();

        if (is_order) {
            let pool = implements::get_mut_pool<X, Y>(global, is_order);

            // check if amount_out > amount_out_min
            let amount_out = implements::get_amounts_out<X, Y>(pool, amount_in);
            assert!(amount_out >= amount_out_min, ERR_INSUFFICIENT_OUTPUT_AMOUNT);

            let coins_in = coin::split(&mut coins_in_origin, amount_in, ctx);
            let (zero, coins_out) = implements::swap_coins_for_coins<X, Y>(pool, clock, coins_in, coin::zero(ctx), ctx);
            coin::destroy_zero(zero);
            assert!(coin::value(&coins_out) >= amount_out_min, ERR_INSUFFICIENT_OUTPUT_AMOUNT);

            transfer::public_transfer(coins_in_origin, tx_context::sender(ctx));
            transfer::public_transfer(coins_out, tx_context::sender(ctx));
        }
         else {
            let pool = implements::get_mut_pool<Y, X>(global, !is_order);

            // check if amount_out > amount_out_min
            let amount_out = implements::get_amounts_out<Y, X>(pool, amount_in);
            assert!(amount_out >= amount_out_min, ERR_INSUFFICIENT_OUTPUT_AMOUNT);

            let coins_in = coin::split(&mut coins_in_origin, amount_in, ctx);
            let (coins_out, zero) = implements::swap_coins_for_coins<Y, X>(pool, clock, coin::zero(ctx), coins_in, ctx);
            coin::destroy_zero(zero);
            assert!(coin::value(&coins_out) >= amount_out_min, ERR_INSUFFICIENT_OUTPUT_AMOUNT);

            transfer::public_transfer(coins_in_origin, tx_context::sender(ctx));
            transfer::public_transfer(coins_out, tx_context::sender(ctx));
        }
    }

    

    public entry fun swap_coinA_for_exact_coinB<X, Y>(
        global: &mut Global,
        clock: &Clock,
        coins_in_origin: Coin<X>,
        amount_in_max: u64,
        amount_out: u64,
        ctx: &mut TxContext
    ) {
        let is_order = implements::is_order<X, Y>();
        
        if (is_order) {
            let pool = implements::get_mut_pool<X, Y>(global, is_order);

            let amount_in = implements::get_amounts_in<X, Y>(pool, amount_out);
            assert!(amount_in <= amount_in_max, ERR_INSUFFICIENT_INPUT_AMOUNT);

            let coins_in = coin::split(&mut coins_in_origin, amount_in, ctx);
            let (zero, coins_out) = implements::swap_coins_for_coins<X, Y>(pool, clock, coins_in, coin::zero(ctx), ctx);
            coin::destroy_zero(zero);
            implements::return_remaining_coin(coins_in_origin, ctx);
            transfer::public_transfer(coins_out, tx_context::sender(ctx));
        } else {
            let pool = implements::get_mut_pool<Y, X>(global, !is_order);

            let amount_in = implements::get_amounts_in<Y, X>(pool, amount_out);
            assert!(amount_in <= amount_in_max, ERR_INSUFFICIENT_INPUT_AMOUNT);

            let coins_in = coin::split(&mut coins_in_origin, amount_in, ctx);
            let (coins_out, zero) = implements::swap_coins_for_coins<Y, X>(pool, clock, coin::zero(ctx), coins_in, ctx);
            coin::destroy_zero(zero);
            implements::return_remaining_coin(coins_in_origin, ctx);
            transfer::public_transfer(coins_out, tx_context::sender(ctx));
        }

       
    }
}

#[test_only]
module swap::tests {
    use std::vector;
    use sui::coin::{mint_for_testing as mint, burn_for_testing as burn};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use swap::implements::{Self};
    use swap::interface;
    use sui::clock::{Self, Clock};

    // use std::debug;

    const TEST_ERROR: u64 = 10000;

    const ERR_NO_PERMISSIONS: u64 = 101;
    const ERR_EMERGENCY: u64 = 102;
    const ERR_GLOBAL_MISMATCH: u64 = 103;
    const ERR_UNEXPECTED_RETURN: u64 = 104;
    const ERR_EMPTY_COINS: u64 = 105;

    /// Gonna be our test token.
    struct TestCoin1 has drop {}
    struct TestCoin2 has drop {}
    struct TestCoin3 has drop {}

    #[test]
    fun test_add_remove_lp_basic() {
        let scenario = scenario();
        let (owner, one, _) = people();
        next_tx(&mut scenario, owner);
        {
            let test = &mut scenario;
            implements::init_for_testing(ctx(test));
            let clock = clock::create_for_testing(ctx(test));
            clock::share_for_testing(clock);
        };
        let (lp, return_values);
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let global = test::take_shared<implements::Global>(test);
            let clock = test::take_shared<Clock>(test);
            let is_order = implements::is_order<TestCoin1, TestCoin2>();
            if (!implements::has_registered<TestCoin1, TestCoin2>(&global)) {
                implements::register_pool<TestCoin1, TestCoin2>(&mut global, is_order);
            };

            let pool = implements::get_mut_pool<TestCoin1, TestCoin2>(&mut global, is_order);

            (lp, return_values) = implements::add_liquidity<TestCoin1, TestCoin2>(
                pool,
                mint<TestCoin1>(10000, ctx(test)), 
                10000,
                mint<TestCoin2>(20000, ctx(test)), 
                10000,
                is_order,
                ctx(test)
            );

            assert!(vector::length(&return_values) == 3, ERR_UNEXPECTED_RETURN);

            test::return_shared(clock);
            test::return_shared(global);
        };

        
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let global = test::take_shared<implements::Global>(test);
            let clock = test::take_shared<Clock>(test);

            let is_order = implements::is_order<TestCoin1, TestCoin2>();
            let pool = implements::get_mut_pool<TestCoin1, TestCoin2>(&mut global, is_order);

            let (coin_x, coin_y) = implements::remove_liquidity(
                pool, 
                lp,
                is_order, 
                ctx(test));

            burn(coin_x);
            burn(coin_y);
            test::return_shared(clock);
            test::return_shared(global);
        };

        test::end(scenario);
    }

    #[test]
    fun test_swap() {
        let scenario = scenario();
        let (owner, one, _) = people();

        next_tx(&mut scenario, owner);
        {
            let test = &mut scenario;
            implements::init_for_testing(ctx(test));
            let clock = clock::create_for_testing(ctx(test));
            clock::share_for_testing(clock);
        };

        let (lp, return_values);
        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let global = test::take_shared<implements::Global>(test);
            let clock = test::take_shared<Clock>(test);
            let is_order = implements::is_order<TestCoin1, TestCoin2>();
            if (!implements::has_registered<TestCoin1, TestCoin2>(&global)) {
                implements::register_pool<TestCoin1, TestCoin2>(&mut global, is_order);
            };

            let pool = implements::get_mut_pool<TestCoin1, TestCoin2>(&mut global, is_order);

            (lp, return_values) = implements::add_liquidity(
                pool,
                mint<TestCoin1>(10000, ctx(test)), 
                10000,
                mint<TestCoin2>(20000, ctx(test)), 
                10000,
                is_order,
                ctx(test)
            );

            implements::set_swap_fee<TestCoin1, TestCoin2>(
                pool,
                30,
                100,
                ctx(test)
            );

            assert!(vector::length(&return_values) == 3, ERR_UNEXPECTED_RETURN);
            
            test::return_shared(clock);
            test::return_shared(global);
        };

        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let global = test::take_shared<implements::Global>(test);
            let clock = test::take_shared<Clock>(test);

            interface::swap_exact_coinA_for_coinB<TestCoin1, TestCoin2>(
                &mut global,
                &clock,
                mint<TestCoin1>(1000, ctx(test)),
                1000,
                100,
                ctx(test),
            );
            
            test::return_shared(clock);
            test::return_shared(global);
        };

        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let global = test::take_shared<implements::Global>(test);
            let clock = test::take_shared<Clock>(test);

            interface::swap_exact_coinA_for_coinB<TestCoin2, TestCoin1>(
                &mut global,
                &clock,
                mint<TestCoin2>(1000, ctx(test)),
                1000,
                100,
                ctx(test),
            );
            
            test::return_shared(clock);
            test::return_shared(global);
        };

        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let global = test::take_shared<implements::Global>(test);
            let clock = test::take_shared<Clock>(test);

            interface::swap_coinA_for_exact_coinB<TestCoin1, TestCoin2>(
                &mut global,
                &clock,
                mint<TestCoin1>(1000, ctx(test)),
                10000,
                1000,
                ctx(test)
            );
            
            test::return_shared(clock);
            test::return_shared(global);
        };

        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let global = test::take_shared<implements::Global>(test);
            let clock = test::take_shared<Clock>(test);

            interface::swap_coinA_for_exact_coinB<TestCoin2, TestCoin1>(
                &mut global,
                &clock,
                mint<TestCoin2>(1000, ctx(test)),
                10000,
                1000,
                ctx(test)
            );
            
            test::return_shared(clock);
            test::return_shared(global);
        };

        next_tx(&mut scenario, one);
        {
            let test = &mut scenario;
            let global = test::take_shared<implements::Global>(test);
            let clock = test::take_shared<Clock>(test);

            let is_order = implements::is_order<TestCoin1, TestCoin2>();
            let pool = implements::get_mut_pool<TestCoin1, TestCoin2>(&mut global, is_order);

            let (coin_x, coin_y) = implements::remove_liquidity(
                pool, 
                lp,
                is_order, 
                ctx(test));

            burn(coin_x);
            burn(coin_y);
            test::return_shared(clock);
            test::return_shared(global);
        };
       
        test::end(scenario);
    }

    // utilities
    fun scenario(): Scenario { test::begin(@0x1) }
    fun people(): (address, address, address) { (@0xBEEF, @0x1111, @0x2222) }
}