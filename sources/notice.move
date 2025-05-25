module notice::protocol {
    use std::error;
    use std::signer;
    use std::vector;
    use std::string;
    use std::timestamp;

    // Import Aptos framework modules for fungible token, object store, and metadata
    use aptos_framework::fungible_asset::{Self, FungibleStore, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object, ExtendRef};

    // Address where the module is deployed
    const MODULE_ADDR: address = @notice;

    // Error codes used throughout the protocol logic
    const EALREADY_INITIALIZED: u64 = 1;
    const EINSUFFICIENT_BALANCE: u64 = 2;
    const EINVALID_NOTICE_RULE: u64 = 3;
    const EINVALID_NOTICE_REQUEST: u64 = 4;
    // Defines how rewards are distributed to participants
    // Additional custom rules can be added here in the future as needed
    enum RewardRule has copy, drop, store {
        FIFO, // reward given to first N noticers
        INTERVAL //
        // CUSTOM rules can be added later for more advanced reward strategies
    }

    // Stores admin config for the notice module
    struct NoticeConfig has key {
        admin: address
    }

    // Global store holding all notices
    struct NoticeStore has key {
        notices: vector<Notice>,
        next_notice_idx: u64
    }

    // Main Notice structure
    struct Notice has key, store {
        id: u64,
        creator: address,
        title: string::String,
        contents: string::String,
        reward_token: Object<Metadata>,

        // reward configuration
        reward_per_view: u64,
        reward_per_like: u64,
        reward_per_comment: u64,
        view_rule: RewardRule,
        like_rule: RewardRule,
        comment_rule: RewardRule,
        view_max_winners: u64,
        like_max_winners: u64,
        comment_max_winners: u64,

        // interval N (shared across all INTERVAL rules)
        interval_n: u64,

        // unified reward token storage
        reward_store: Object<FungibleStore>,
        reward_token_extend_ref: ExtendRef,

        // participants
        view_list: vector<address>,
        like_list: vector<address>,
        comment_list: vector<CommentData>
    }

    // Represents each comment data
    public struct CommentData has copy, drop, store {
        user: address,
        text: string::String
    }

    // Tracks which notices a user has submitted to prevent duplicates
    struct NoticeActionStore has key {
        view_list: vector<u64>,
        like_list: vector<u64>,
        comment_list: vector<u64>
    }

    // Initializes the notice store and admin config (must be called once)
    public entry fun init(signer: &signer) {
        assert!(signer::address_of(signer) == MODULE_ADDR, error::permission_denied(1));
        assert!(!exists<NoticeConfig>(MODULE_ADDR), EALREADY_INITIALIZED);
        assert!(!exists<NoticeStore>(MODULE_ADDR), EALREADY_INITIALIZED);

        move_to(signer, NoticeConfig { admin: MODULE_ADDR });

        move_to(
            signer,
            NoticeStore { notices: vector::empty(), next_notice_idx: 0 }
        );
    }

    // Changes the module admin address (only callable by current admin)
    public entry fun set_admin(admin: &signer, new_admin: address) acquires NoticeConfig {
        let config = borrow_global_mut<NoticeConfig>(MODULE_ADDR);
        assert!(signer::address_of(admin) == config.admin, error::permission_denied(1));
        config.admin = new_admin;
    }

    // Maps numeric input to the internal RewardRule enum type
    fun match_reward_rule(reward_rule_val: u8): RewardRule {
        if (reward_rule_val == 0) {
            RewardRule::FIFO
        } else if (reward_rule_val == 1) {
            RewardRule::INTERVAL
        } else {
            abort EINVALID_NOTICE_RULE
        }
    }

    fun reward_rule_to_u8(rule: RewardRule): u8 {
        if (rule == RewardRule::FIFO) { 0 }
        else if (rule == RewardRule::INTERVAL) { 1 }
        else {
            abort EINVALID_NOTICE_RULE
        }
    }

    // Creates a new notice with reward configuration and options
    // Transfers reward tokens to internal store and registers the notice metadata
    public entry fun create_notice(
        caller: &signer,
        notice_idx: u64,
        title: string::String,
        contents: string::String,
        reward_token: Object<Metadata>,
        view_rule_val: u8,
        like_rule_val: u8,
        comment_rule_val: u8,
        interval_n: u64,
        reward_per_view: u64,
        reward_per_like: u64,
        reward_per_comment: u64,
        view_max_winners: u64,
        like_max_winners: u64,
        comment_max_winners: u64
    ) acquires NoticeStore {
        let notice_store = borrow_global_mut<NoticeStore>(MODULE_ADDR);
        assert!(notice_idx == notice_store.next_notice_idx, EINVALID_NOTICE_REQUEST);

        let caller_addr = signer::address_of(caller);
        let constructor = &object::create_object(caller_addr);
        let reward_store = fungible_asset::create_store(constructor, reward_token);
        let extend_ref = object::generate_extend_ref(constructor);

        let caller_store =
            primary_fungible_store::ensure_primary_store_exists(
                caller_addr, reward_token
            );

        let amount_view = reward_per_view * view_max_winners;
        let amount_like = reward_per_like * like_max_winners;
        let amount_comment = reward_per_comment * comment_max_winners;
        let total_amount = amount_view + amount_like + amount_comment;

        let balance = fungible_asset::balance(caller_store);
        assert!(balance >= total_amount, error::invalid_argument(EINSUFFICIENT_BALANCE));

        let reward = fungible_asset::withdraw(caller, caller_store, total_amount);
        fungible_asset::deposit(reward_store, reward);

        let notice = Notice {
            id: notice_idx,
            creator: caller_addr,
            title,
            contents,
            reward_token,
            reward_per_view,
            reward_per_like,
            reward_per_comment,
            view_rule: match_reward_rule(view_rule_val),
            like_rule: match_reward_rule(like_rule_val),
            comment_rule: match_reward_rule(comment_rule_val),
            view_max_winners,
            like_max_winners,
            comment_max_winners,
            interval_n,
            reward_store,
            reward_token_extend_ref: extend_ref,
            view_list: vector::empty<address>(),
            like_list: vector::empty<address>(),
            comment_list: vector::empty<CommentData>()
        };

        vector::push_back(&mut notice_store.notices, notice);
        notice_store.next_notice_idx = notice_store.next_notice_idx + 1;
    }

    #[view]
    public fun get_notice_info(
        notice_idx: u64
    ): (
        address,
        string::String,
        string::String,
        object::Object<Metadata>,
        u64,
        u8,
        u64,
        u64,
        u8,
        u64,
        u64,
        u8,
        u64,
        u64, 
        vector<address>, // view list
        vector<address>, // like list
        vector<address>, // comment user list
        vector<string::String>, // comment text list
        u64
    ) acquires NoticeStore {
        let notice_store = borrow_global<NoticeStore>(MODULE_ADDR);
        let notice = vector::borrow(&notice_store.notices, notice_idx);

        let comment_users = vector::empty<address>();
        let comment_texts = vector::empty<string::String>();
        let i = 0;
        while (i < vector::length(&notice.comment_list)) {
            let comment = vector::borrow(&notice.comment_list, i);
            vector::push_back(&mut comment_users, comment.user);
            vector::push_back(&mut comment_texts, comment.text);
            i = i + 1;
        };

        let balance = fungible_asset::balance(notice.reward_store);

        (
            notice.creator,
            notice.title,
            notice.contents,
            notice.reward_token,
            notice.reward_per_view,
            reward_rule_to_u8(notice.view_rule),
            notice.view_max_winners,
            notice.reward_per_like,
            reward_rule_to_u8(notice.like_rule),
            notice.like_max_winners,
            notice.reward_per_comment,
            reward_rule_to_u8(notice.comment_rule),
            notice.comment_max_winners,
            notice.interval_n,
            notice.view_list,
            notice.like_list,
            comment_users,
            comment_texts,
            balance
        )
    }

    public entry fun edit_notice(
        caller: &signer,
        notice_idx: u64,
        new_title: string::String,
        new_contents: string::String,
        new_view_rule_val: u8,
        new_like_rule_val: u8,
        new_comment_rule_val: u8,
        new_reward_per_view: u64,
        new_reward_per_like: u64,
        new_reward_per_comment: u64,
        new_view_max_winners: u64,
        new_like_max_winners: u64,
        new_comment_max_winners: u64,
        new_interval_n: u64
    ) acquires NoticeStore, NoticeConfig {
        let config = borrow_global<NoticeConfig>(MODULE_ADDR);
        let signer_addr = signer::address_of(caller);

        let notice_store = borrow_global_mut<NoticeStore>(MODULE_ADDR);
        let notice = vector::borrow_mut(&mut notice_store.notices, notice_idx);

        assert!(
            signer_addr == notice.creator || signer_addr == config.admin,
            error::permission_denied(1)
        );

        let reward_token = notice.reward_token;
        let user_store =
            primary_fungible_store::ensure_primary_store_exists(
                signer_addr, reward_token
            );
        let store_signer =
            object::generate_signer_for_extending(&notice.reward_token_extend_ref);

        // Calculate old and new total reward requirements
        let old_total =
            notice.reward_per_view * notice.view_max_winners
                + notice.reward_per_like * notice.like_max_winners
                + notice.reward_per_comment * notice.comment_max_winners;

        let new_total =
            new_reward_per_view * new_view_max_winners
                + new_reward_per_like * new_like_max_winners
                + new_reward_per_comment * new_comment_max_winners;

        if (new_total > old_total) {
            let diff = new_total - old_total;
            let additional = fungible_asset::withdraw(caller, user_store, diff);
            fungible_asset::deposit(notice.reward_store, additional);
        } else if (old_total > new_total) {
            let refund =
                fungible_asset::withdraw(
                    &store_signer, notice.reward_store, old_total - new_total
                );
            fungible_asset::deposit(user_store, refund);
        };

        notice.title = new_title;
        notice.contents = new_contents;
        notice.view_rule = match_reward_rule(new_view_rule_val);
        notice.like_rule = match_reward_rule(new_like_rule_val);
        notice.comment_rule = match_reward_rule(new_comment_rule_val);
        notice.reward_per_view = new_reward_per_view;
        notice.reward_per_like = new_reward_per_like;
        notice.reward_per_comment = new_reward_per_comment;
        notice.view_max_winners = new_view_max_winners;
        notice.like_max_winners = new_like_max_winners;
        notice.comment_max_winners = new_comment_max_winners;
        notice.interval_n = new_interval_n;
    }

    // Utility function to check if a notice ID exists in a list of submitted notices
    fun contains_id(ids: &vector<u64>, id: u64): bool {
        let i = 0;
        while (i < vector::length(ids)) {
            if (*vector::borrow(ids, i) == id) {
                return true;
            };
            i = i + 1;
        };
        false
    }

    fun distribute_reward(
        user: &signer,
        reward_amount: u64,
        rule: RewardRule,
        current_index: u64,
        max_winners: u64,
        interval_n: u64,
        notice_idx: u64,
        rewarded_list_mut: &mut vector<u64>,
    ) acquires NoticeStore {
        // Skip if already rewarded for this notice
        if (contains_id(rewarded_list_mut, notice_idx)) {
            return;
        };

        let notice_store = borrow_global_mut<NoticeStore>(MODULE_ADDR);
        let notice_ref = vector::borrow_mut(&mut notice_store.notices, notice_idx);

        let reward_store = notice_ref.reward_store;
        let extend_ref = &notice_ref.reward_token_extend_ref;

        let eligible =
            if (rule == RewardRule::FIFO) {
                current_index <= max_winners
            } else if (rule == RewardRule::INTERVAL) {
                interval_n > 0 &&
                current_index % interval_n == 0 &&
                current_index/ interval_n <= max_winners
            } else {
                false
            };

        if (eligible) {
            let user_store =
                primary_fungible_store::ensure_primary_store_exists(
                    signer::address_of(user),
                    fungible_asset::store_metadata(reward_store)
                );

            let store_signer = object::generate_signer_for_extending(extend_ref);
            let reward = fungible_asset::withdraw(&store_signer, reward_store, reward_amount);
            fungible_asset::deposit(user_store, reward);

            vector::push_back(rewarded_list_mut, notice_idx);
        };
    }

    public entry fun view_notice(
        user: &signer, notice_idx: u64
    ) acquires NoticeStore, NoticeActionStore {
        let notice_store = borrow_global_mut<NoticeStore>(MODULE_ADDR);
        let notice = &mut *vector::borrow_mut(&mut notice_store.notices, notice_idx);

        ensure_notice_action_store(user);
        let action_store = borrow_global_mut<NoticeActionStore>(signer::address_of(user));

        vector::push_back(&mut notice.view_list, signer::address_of(user));
        let count = vector::length(&notice.view_list);

        distribute_reward(
            user,
            notice.reward_per_view,
            notice.view_rule,
            count,
            notice.view_max_winners,
            notice.interval_n,
            notice_idx,
            &mut action_store.view_list,
        );
    }

    public entry fun like_notice(
        user: &signer, notice_idx: u64
    ) acquires NoticeStore, NoticeActionStore {
        let notice_store = borrow_global_mut<NoticeStore>(MODULE_ADDR);
        let notice = &mut *vector::borrow_mut(&mut notice_store.notices, notice_idx);

        ensure_notice_action_store(user);
        let action_store = borrow_global_mut<NoticeActionStore>(signer::address_of(user));


        vector::push_back(&mut notice.like_list, signer::address_of(user));
        let count = vector::length(&notice.like_list);

        distribute_reward(
            user,
            notice.reward_per_like,
            notice.like_rule,
            count,
            notice.like_max_winners,
            notice.interval_n,
            notice_idx,
            &mut action_store.like_list
        );
    }

    public entry fun comment_notice(
        user: &signer, notice_idx: u64, comment_text: string::String
    ) acquires NoticeStore, NoticeActionStore {
        let notice_store = borrow_global_mut<NoticeStore>(MODULE_ADDR);
        let notice = &mut *vector::borrow_mut(&mut notice_store.notices, notice_idx);

        ensure_notice_action_store(user);
        let action_store = borrow_global_mut<NoticeActionStore>(signer::address_of(user));

        let comment = CommentData { user: signer::address_of(user), text: comment_text };
        vector::push_back(&mut notice.comment_list, comment);
        let count = vector::length(&notice.comment_list);

        distribute_reward(
            user,
            notice.reward_per_comment,
            notice.comment_rule,
            count,
            notice.comment_max_winners,
            notice.interval_n,
            notice_idx,
            &mut action_store.comment_list
        );
    }

    fun ensure_notice_action_store(user: &signer) {
        let addr = signer::address_of(user);
        if (!exists<NoticeActionStore>(addr)) {
            move_to(user, NoticeActionStore {
                view_list: vector::empty<u64>(),
                like_list: vector::empty<u64>(),
                comment_list: vector::empty<u64>()
            });
        };
    }

    // Finalizes the notice and refunds remaining rewards to the creator
    public entry fun force_finalize_notice(
        caller: &signer, notice_idx: u64
    ) acquires NoticeStore {
        let signer_addr = signer::address_of(caller);
        let notice_store = borrow_global_mut<NoticeStore>(MODULE_ADDR);
        let notice_ref = vector::borrow_mut(&mut notice_store.notices, notice_idx);

        assert!(
            signer_addr == notice_ref.creator,
            error::permission_denied(1)
        );

        refund_remaining_reward(notice_ref);
    }

    fun refund_remaining_reward(notice_ref: &Notice) {
        let reward_token = notice_ref.reward_token;
        let store_signer =
            object::generate_signer_for_extending(&notice_ref.reward_token_extend_ref);

        let remaining = fungible_asset::balance(notice_ref.reward_store);
        if (remaining > 0) {
            let refund =
                fungible_asset::withdraw(
                    &store_signer, notice_ref.reward_store, remaining
                );
            let to_store =
                primary_fungible_store::ensure_primary_store_exists(
                    notice_ref.creator, reward_token
                );
            fungible_asset::deposit(to_store, refund);
        };
    }
}
