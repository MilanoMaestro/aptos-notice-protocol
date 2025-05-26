module tests::notice_test {

    use std::string;
    use std::timestamp;
    use std::option;
    use std::signer;
    use std::vector;

    use aptos_framework::object::{Self};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::primary_fungible_store;
    use notice::protocol;

    #[test(creator = @notice)]
    fun test_init(creator: &signer) {
        // First call to init should succeed
        protocol::init(creator);
    }

    #[test_only]
    fun create_test_fungible_asset(
        creator: &signer
    ): (object::ConstructorRef, object::Object<Metadata>) {
        let constructor = object::create_named_object(creator, b"TEST_TOKEN");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor,
            option::none(),
            string::utf8(b"My Token"),
            string::utf8(b"MTK"),
            6,
            string::utf8(b"http://icon.uri"),
            string::utf8(b"http://project.uri")
        );
        let metadata = object::object_from_constructor_ref<Metadata>(&constructor);
        (constructor, metadata)
    }

    #[test(creator = @notice, framework = @0x1)]
    fun test_create_notice_basic(creator: &signer, framework: &signer) {
        // Init protocol and time
        timestamp::set_time_has_started_for_testing(framework);
        timestamp::update_global_time_for_test_secs(1);
        protocol::init(creator);

        // Setup test token and deposit
        let (constructor, token) = create_test_fungible_asset(creator);
        let mint_ref = fungible_asset::generate_mint_ref(&constructor);
        let minted = fungible_asset::mint(&mint_ref, 300);
        let creator_store =
            primary_fungible_store::ensure_primary_store_exists(
                signer::address_of(creator), token
            );
        fungible_asset::deposit(creator_store, minted);

        // Create notice
        protocol::create_notice(
            creator,
            0,
            string::utf8(b"My Notice"),
            string::utf8(b"Details of the notice"),
            token,
            0,
            0,
            0, // rules = FIFO
            1, // interval_n
            10,
            20,
            30, // reward amounts
            2,
            3,
            4 // max winners
        );

        // Verify notice info
        let (
            creator_addr,
            title,
            contents,
            reward_token,
            reward_per_view,
            view_rule,
            view_max_winners,
            reward_per_like,
            like_rule,
            like_max_winners,
            reward_per_comment,
            comment_rule,
            comment_max_winners,
            interval_n,
            view_list, 
            like_list, 
            comment_list, 
            _,
            reward_store_balance 
        ) = protocol::get_notice_info(0);

        // Field checks
        assert!(creator_addr == signer::address_of(creator), 100);
        assert!(title == string::utf8(b"My Notice"), 101);
        assert!(contents == string::utf8(b"Details of the notice"), 102);
        assert!(reward_token == token, 103);
        assert!(reward_per_view == 10, 104);
        assert!(view_rule == 0, 105);
        assert!(view_max_winners == 2, 106);
        assert!(reward_per_like == 20, 107);
        assert!(like_rule == 0, 108);
        assert!(like_max_winners == 3, 109);
        assert!(reward_per_comment == 30, 110);
        assert!(comment_rule == 0, 111);
        assert!(comment_max_winners == 4, 112);
        assert!(interval_n == 1, 113);

        // Initial counts
        assert!(vector::length(&view_list) == 0, 120);
        assert!( vector::length(&like_list) == 0, 121);
        assert!( vector::length(&comment_list) == 0, 122);

        // Notice store balance 

        assert!(reward_store_balance == 200, 130);

        
        // Balance check: 300 - (10*2 + 20*3 + 30*4) = 100
        let balance = fungible_asset::balance(creator_store);
        
        assert!(balance == 100, 131);
    }

    #[test(creator = @notice, user1 = @0x2, user2 = @0x3, user3 = @0x4, framework = @0x1)]
    fun test_view_like_reward_fifo_limit(
        creator: &signer, user1: &signer, user2: &signer, user3: &signer, framework: &signer
    ) {
        timestamp::set_time_has_started_for_testing(framework);
        timestamp::update_global_time_for_test_secs(1);
        protocol::init(creator);

        let (constructor, token) = create_test_fungible_asset(creator);
        let mint_ref = fungible_asset::generate_mint_ref(&constructor);
        let minted = fungible_asset::mint(&mint_ref, 10000);
        let creator_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(creator), token);
        fungible_asset::deposit(creator_store, minted);

        protocol::create_notice(
            creator,
            0,
            string::utf8(b"FIFO Notice"),
            string::utf8(b"FIFO reward test"),
            token,
            0, 0, 0, // all FIFO
            1,
            10, 10, 0, // view, like reward
            2, 2, 0 // max winners
        );
        let (_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, reward_balance) =
            protocol::get_notice_info(0);

        assert!(reward_balance == 40, 200);
        
        protocol::view_notice(user1, 0);
        protocol::view_notice(user2, 0);
        protocol::view_notice(user3, 0);

        protocol::like_notice(user1, 0);
        protocol::like_notice(user2, 0);
        protocol::like_notice(user3, 0);

        let user1_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(user1), token);
        let user2_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(user2), token);
        let user3_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(user3), token);

        let balance1 = fungible_asset::balance(user1_store); // 10(view) + 10(like) = 20
        let balance2 = fungible_asset::balance(user2_store); // 20
        let balance3 = fungible_asset::balance(user3_store); // 0

        assert!(balance1 == 20, 201);
        assert!(balance2 == 20, 202);
        assert!(balance3 == 0, 203);
    }
    
    #[test(creator = @notice, u1 = @0x2, u2 = @0x3, u3 = @0x4, u4 = @0x5, u5 = @0x6, u6 = @0x7, framework = @0x1)]
    fun test_view_reward_interval_with_max_winners_limit(
        creator: &signer, u1: &signer, u2: &signer, u3: &signer,
        u4: &signer, u5: &signer, u6: &signer, framework: &signer
    ) {
        timestamp::set_time_has_started_for_testing(framework);
        timestamp::update_global_time_for_test_secs(1);
        protocol::init(creator);

        let (constructor, token) = create_test_fungible_asset(creator);
        let mint_ref = fungible_asset::generate_mint_ref(&constructor);
        let minted = fungible_asset::mint(&mint_ref, 100);
        let creator_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(creator), token);
        fungible_asset::deposit(creator_store, minted);

        // interval rule 2 max winners 2 reward per view 5
        protocol::create_notice(
            creator,
            0,
            string::utf8(b"Interval with max"),
            string::utf8(b"test"),
            token,
            1, 0, 0,
            2,
            5, 0, 0,
            2, 0, 0
        );

        // view index 1
        protocol::view_notice(u1, 0);
        // view index 2
        protocol::view_notice(u2, 0);
        // view index 3
        protocol::view_notice(u3, 0);
        // view index 4
        protocol::view_notice(u4, 0);
        // // view index 5
        protocol::view_notice(u5, 0);
        // // view index 6
        protocol::view_notice(u6, 0);

        let b1 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u1), token));
        let b2 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u2), token));
        let b3 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u3), token));
        let b4 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u4), token));
        let b5 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u5), token));
        let b6 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u6), token));

        assert!(b1 == 0, 301);
        assert!(b2 == 5, 302);
        assert!(b3 == 0, 303);
        assert!(b4 == 5, 304);
        assert!(b5 == 0, 305);
        assert!(b6 == 0, 306);
    }

    #[test(creator = @notice, u1 = @0x2, u2 = @0x3, u3 = @0x4, u4 = @0x5, framework = @0x1)]
    fun test_comment_fifo_reward_and_persistence(
        creator: &signer, u1: &signer, u2: &signer, u3: &signer, u4: &signer, framework: &signer
    ) {
        timestamp::set_time_has_started_for_testing(framework);
        timestamp::update_global_time_for_test_secs(1);
        protocol::init(creator);

        let (constructor, token) = create_test_fungible_asset(creator);
        let mint_ref = fungible_asset::generate_mint_ref(&constructor);
        let minted = fungible_asset::mint(&mint_ref, 100);
        let creator_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(creator), token);
        fungible_asset::deposit(creator_store, minted);

        // reward per comment = 15, max winners = 2, rule = FIFO
        protocol::create_notice(
            creator,
            0,
            string::utf8(b"Comment Persistence"),
            string::utf8(b"Test"),
            token,
            0, 0, 0,
            1,
            0, 0, 15,
            0, 0, 2
        );

        protocol::comment_notice(u1, 0, string::utf8(b"First comment"));
        protocol::comment_notice(u2, 0, string::utf8(b"Second comment"));
        protocol::comment_notice(u3, 0, string::utf8(b"Third comment"));
        protocol::comment_notice(u4, 0, string::utf8(b"Fourth comment"));

        let b1 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u1), token));
        let b2 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u2), token));
        let b3 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u3), token));
        let b4 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u4), token));

        assert!(b1 == 15, 601); // rewarded
        assert!(b2 == 15, 602); // rewarded
        assert!(b3 == 0, 603);  // not rewarded
        assert!(b4 == 0, 604);  // not rewarded

        let (_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, comment_users, comment_texts, _) = protocol::get_notice_info(0);

        assert!(vector::length(&comment_users) == 4, 400);
        assert!(vector::length(&comment_texts) == 4, 401);
        assert!(*vector::borrow(&comment_users, 0) == signer::address_of(u1), 402);
        assert!(*vector::borrow(&comment_users, 1) == signer::address_of(u2), 403);
        assert!(*vector::borrow(&comment_users, 2) == signer::address_of(u3), 404);
        assert!(*vector::borrow(&comment_users, 3) == signer::address_of(u4), 405);

        assert!(*vector::borrow(&comment_texts, 0) == string::utf8(b"First comment"), 406);
        assert!(*vector::borrow(&comment_texts, 1) == string::utf8(b"Second comment"), 407);
        assert!(*vector::borrow(&comment_texts, 2) == string::utf8(b"Third comment"), 408);
        assert!(*vector::borrow(&comment_texts, 3) == string::utf8(b"Fourth comment"), 409);
    }

    #[test(creator = @notice, u1 = @0x2, framework = @0x1)]
    fun test_multiple_comments_only_one_reward(
        creator: &signer, u1: &signer, framework: &signer
    ) {
        timestamp::set_time_has_started_for_testing(framework);
        timestamp::update_global_time_for_test_secs(1);
        protocol::init(creator);

        let (constructor, token) = create_test_fungible_asset(creator);
        let mint_ref = fungible_asset::generate_mint_ref(&constructor);
        let minted = fungible_asset::mint(&mint_ref, 100);
        let creator_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(creator), token);
        fungible_asset::deposit(creator_store, minted);

        protocol::create_notice(
            creator,
            0,
            string::utf8(b"Multi Comment One Reward"),
            string::utf8(b"Test"),
            token,
            0, 0, 0,
            1,
            0, 0, 20,
            0, 0, 1
        );

        protocol::comment_notice(u1, 0, string::utf8(b"Comment 1"));
        protocol::comment_notice(u1, 0, string::utf8(b"Comment 2"));
        protocol::comment_notice(u1, 0, string::utf8(b"Comment 3"));

        let balance = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u1), token));
        assert!(balance == 20, 501);

        let (_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, users, texts, _) = protocol::get_notice_info(0);
        assert!(vector::length(&users) == 3, 502);
        assert!(vector::length(&texts) == 3, 503);
    }

    #[test(creator = @notice, u1 = @0x2, u2 = @0x3, framework = @0x1)]
    fun test_mixed_action_balances(
        creator: &signer, u1: &signer, u2: &signer, framework: &signer
    ) {
        timestamp::set_time_has_started_for_testing(framework);
        timestamp::update_global_time_for_test_secs(1);
        protocol::init(creator);

        let (constructor, token) = create_test_fungible_asset(creator);
        let mint_ref = fungible_asset::generate_mint_ref(&constructor);
        let minted = fungible_asset::mint(&mint_ref, 300);
        let creator_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(creator), token);
        fungible_asset::deposit(creator_store, minted);

        // reward: 10 per view, 15 per like, 20 per comment FIFO, max 1 each
        protocol::create_notice(
            creator,
            0,
            string::utf8(b"Mixed Actions"),
            string::utf8(b"Test mix actions"),
            token,
            0, 0, 0,
            1,
            10, 15, 20,
            1, 1, 1
        );

        // User1: view + like + comment :should receive all rewards
        protocol::view_notice(u1, 0);
        protocol::like_notice(u1, 0);
        protocol::comment_notice(u1, 0, string::utf8(b"Nice post"));

        // User2: view + like + comment :no reward
        protocol::view_notice(u2, 0);
        protocol::like_notice(u2, 0);
        protocol::comment_notice(u2, 0, string::utf8(b"Me too"));

        let b1 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u1), token));
        let b2 = fungible_asset::balance(primary_fungible_store::ensure_primary_store_exists(signer::address_of(u2), token));

        assert!(b1 == 45, 601); // 10 + 15 + 20
        assert!(b2 == 0, 602);  // no rewards left
    }
}
