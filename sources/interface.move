module swap::interface {
    use std::vector;

    use sui::coin::{Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};

    use swap::implements::{Self, Global};

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
}