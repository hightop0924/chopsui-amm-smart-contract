module swap::interface {
    use std::vector;

    use sui::coin::{Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use swap::implements::{Self, Global, LP, Pool};

    const ERR_NO_PERMISSIONS: u64 = 101;
    const ERR_EMERGENCY: u64 = 102;
    const ERR_GLOBAL_MISMATCH: u64 = 103;
    const ERR_UNEXPECTED_RETURN: u64 = 104;
    const ERR_EMPTY_COINS: u64 = 105;

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

        // let lp_val = vector::pop_back(&mut return_values);
        // let coin_x_val = vector::pop_back(&mut return_values);
        // let coin_y_val = vector::pop_back(&mut return_values);

        transfer::public_transfer(
            lp,
            tx_context::sender(ctx)
        );

        // let global = implements::global_id<X, Y>(pool);
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

    public entry fun init_pool<X, Y>(
        global: &mut Global,
        _:u64, //fee_numerator: u64,
        _:u64, //fee_denominator: u64,
        _: &mut TxContext
    ) {
        let is_order = implements::is_order<X, Y>();

        implements::register_pool<X, Y>(
            global,
            is_order
        );
    }

    public entry fun swap_exact_coinA_for_coinB<X, Y>(
        global: &mut Global,
        coin_a: Coin<X>,
        amount_a_in: u64,
        amount_b_out_min: u64,
        ctx: &mut TxContext
    ) {
        implements::swap_exact_coinA_for_coinB<X, Y>(
            global,
            coin_a,
            amount_a_in,
            amount_b_out_min,
            ctx
        );
    }

    public entry fun swap_coinA_for_exact_coinB<X, Y>(
        global: &mut Global,
        coin_a: Coin<X>,
        amount_a_max: u64,
        amount_b_out: u64,
        ctx: &mut TxContext
    ) {
        implements::swap_coinA_for_exact_coinB<X, Y>(
            global,
            coin_a,
            amount_a_max,
            amount_b_out,
            ctx
        );
    }

    public entry fun set_fee_config<X, Y>(
        global: &mut Global,
        pool: &mut Pool<X, Y>,
        fee_numerator: u64,
        fee_denominator: u64,
        ctx: &mut TxContext
    ) {
        implements::set_fee_config<X, Y>(
            global,
            pool,
            fee_numerator,
            fee_denominator,
            ctx
        );
    }
}