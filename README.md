# aptos-notice-protocol

An Aptos Move module for managing on-chain notice actions and reward distribution.  
This protocol supports configurable rules for views, likes, and comments, including interval-based and FIFO logic.  
Rewards are distributed in real time without requiring a finalize phase

---

## 📦 Package Info

```toml
[package]
name = "Notice"
version = "0.0.1"
authors = ["MilanoM"]

[addresses]
notice = "<deployed_module_address>"
tests = "0xC0FFEE"
std = "0x1"
aptos_std = "0x1"
aptos_framework = "0x1"

[dependencies]
AptosFramework = {
  git = "https://github.com/aptos-labs/aptos-core.git",
  rev = "main",
  subdir = "aptos-move/framework/aptos-framework"
}
```

---

## ⚙️ Module: `notice::protocol`

### Structs

- **NoticeConfig**  
  Stores admin address for management functions.

- **Notice**  
  Represents a public post (notice) with metadata and reward configurations.  
  Includes reward tracking by action type (view, like, comment).

- **CommentData**  
  Stores comment text and address of the commenter.

- **NoticeStore**  
  Holds all notices and controls auto-incremental index.

- **NoticeActionStore**  
  Per-user structure to prevent duplicate rewards (1 view/like per notice, comment can repeat but reward once).

- **RewardRule** (enum)
  - `FIFO` (0): Rewards are given to the first N users.
  - `INTERVAL` (1): Rewards are distributed at every N-th participant (e.g., every 10th viewer).

---

### View Functions

- **`get_notice_info(notice_idx)`**  
  Returns:
  - creator
  - title
  - contents
  - reward_token
  - reward_per_view, reward_per_like, reward_per_comment
  - view_rule, like_rule, comment_rule
  - view_max_winners, like_max_winners, comment_max_winners
  - interval_n
  - view_list (addresses)
  - like_list (addresses)
  - comment_users (addresses)
  - comment_texts (strings)
  - reward_store_balance

---

### Entry Functions

- **`init(signer)`**  
  Initializes admin and notice storage. Only callable by `@notice`.

- **`set_admin(admin, new_admin)`**  
  Changes admin address. Callable only by current admin.

- **`create_notice(...)`**  
  Creates a new notice with reward configuration for view, like, comment.  
  Mints reward pool by splitting tokens per action and depositing into internal stores.

- **`edit_notice(...)`**  
  Allows creator or admin to update metadata or reward terms.  
  Handles diff-based token adjustment (withdraw/deposit if reward amounts change).

- **`view_notice(user, creator, notice_id)`**  
  Adds a user view (ensuring no duplicate via NoticeActionStore).  
  Issues reward if eligible (according to FIFO or INTERVAL).

- **`like_notice(user, creator, notice_id)`**  
  Similar to view: tracks user, issues reward once.

- **`comment_notice(user, creator, notice_id, comment_text)`**  
  Allows multiple comments but only rewards the first per user per notice.

- **`force_finalize_notice(...)`**  
  Ends a notice and refunds remaining tokens to the creator from all 3 stores.

---

### Internal Logic

- **`distribute_reward(...)`**  
  Issues reward to the user using:

  - FIFO: reward if count < max
  - INTERVAL: reward if count % interval == 0

- **`refund_remaining_reward(...)`**  
  At finalize time, withdraws all balances from reward stores and returns to creator.

---

## 🧪 Testing

Test coverage includes:

- Basic notice creation
- Reward distribution for view, like, and comment (FIFO and INTERVAL)
- Reward limits
- Comment persistence after reward limit
- Duplicate reward prevention

---

## 🛠 Build & Deploy

```bash
# Set Move.toml
export NOTICE_ADDR=0x... # your notice module address

# Compile
aptos move compile

# Run tests
aptos move test
```

## 🧭 Future Enhancements

- Add support for on-chain comment moderation or deletion
- Add Merkle-proof support for reward verification in INTERVAL mode
- Event emission for indexing
- Batch commit logic (off-chain queuing + on-chain sync)
