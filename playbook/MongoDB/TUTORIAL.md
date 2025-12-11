# MongoDB 实用教程

本教程涵盖本地连接、基础 CRUD、索引操作，以及 MongoDB 核心特性与原理（副本集、分片、索引）。命令基于 MongoDB 8.x，使用 `mongosh`。

## 1. 连接本地 MongoDB

```bash
# 无认证（仅在未启用认证时）
mongosh --host 192.168.31.140 --port 27017

# 使用管理员账号（示例凭据）
mongosh -u admin -p 'YourPassword' --authenticationDatabase admin --host 192.168.31.140 --port 27017
```

VS Code MongoDB 插件连接 URI（复制即可用）：

```
# 无认证（仅测试环境）
mongodb://192.168.31.140:27017

# 启用认证（示例凭据）
mongodb://admin:YourPassword@192.168.31.140:27017/admin?authMechanism=SCRAM-SHA-256
```

## 2. 基础 CRUD 示例

以下示例使用数据库 `demo`、集合 `users`。

```javascript
use demo;

// 插入单条
db.users.insertOne({ name: "Alice", age: 30, city: "Beijing" });

// 插入多条
db.users.insertMany([
  { name: "Bob", age: 28, city: "Shanghai" },
  { name: "Cindy", age: 32, city: "Shenzhen" }
]);

// 读取（查询全部，限制字段）
db.users.find({}, { _id: 0, name: 1, age: 1 }).pretty();

// 条件查询 + 排序 + 限制
db.users.find({ age: { $gte: 30 } }).sort({ age: -1 }).limit(5);

// 更新单条（set）
db.users.updateOne({ name: "Alice" }, { $set: { age: 31 } });

// 批量更新（inc）
db.users.updateMany({ city: "Shanghai" }, { $inc: { age: 1 } });

// 替换文档（全量覆盖）
db.users.replaceOne({ name: "Bob" }, { name: "Bob", age: 29, city: "Suzhou" });

// 删除
db.users.deleteOne({ name: "Cindy" });
db.users.deleteMany({ city: "Shenzhen" });
```

## 3. 索引操作

```javascript
// 创建单字段索引（升序）
db.users.createIndex({ name: 1 });

// 创建复合索引（常用于查询条件组合）
db.users.createIndex({ city: 1, age: -1 });

// 唯一索引
db.users.createIndex({ email: 1 }, { unique: true });

// 前缀查询优化示例：查询 city+age 前缀
// 会命中 {city:1, age:-1} 复合索引
db.users.find({ city: "Beijing" }).sort({ age: -1 });

// 查看索引
db.users.getIndexes();

// 删除索引
db.users.dropIndex({ name: 1 });
```

**索引要点：**
- 复合索引遵循“最左前缀”原则。
- 谨慎创建过多索引，写入成本和存储都会上升。
- 使用 `explain("executionStats")` 分析查询计划，确认是否命中索引。

## 4. 事务（副本集 / 分片集群可用）

```javascript
// 需要在会话中使用
tx = db.getMongo().startSession();
coll = tx.getDatabase("demo").users;

tx.startTransaction();
try {
  coll.insertOne({ name: "TxUser" });
  coll.updateOne({ name: "Alice" }, { $set: { city: "Hangzhou" } });
  tx.commitTransaction();
} catch (e) {
  tx.abortTransaction();
  throw e;
} finally {
  tx.endSession();
}
```

## 5. Oplog 详解

### 5.1 Oplog 存放位置

Oplog（操作日志）存放在 MongoDB 的 `local` 数据库中，具体集合为 `oplog.rs`。该集合记录了所有对数据库的写操作，确保副本集中的数据一致性。

### 5.2 日志写满后的操作

当 Oplog 写满时，MongoDB 会自动删除最旧的日志条目，以便为新的写操作腾出空间。这种机制确保了 Oplog 的大小保持在配置的限制内，通常是通过 `replSetOplogSizeMB` 参数进行设置。

## 6. MongoDB 核心特性与原理

### 6.1 副本集 (Replica Set)

#### 6.1.1 角色与基础架构
- **Primary**：唯一可写节点，接受所有写操作，写入到本地 oplog。
- **Secondary**：只读副本，从 Primary 或其他 Secondary 拉取 oplog 进行异步复制。
- **Arbiter**：仅参与选举投票，不存储数据，不能成为 Primary，用于奇数节点投票（避免平票）。
- **Hidden/Delayed**：隐藏节点不对外提供读服务，延迟节点可用于备份或历史数据查询，防止误操作立即同步。

#### 6.1.2 Oplog 复制机制

**Oplog 结构**：
- 存储于 `local.oplog.rs` 集合（固定大小的 capped collection）。
- 每条 oplog 记录一个操作，包含字段：
  ```javascript
  {
    "ts": Timestamp(1702275890, 1),  // 操作时间戳（秒 + 递增序列号）
    "t": NumberLong(3),               // Term 编号（选举任期）
    "h": NumberLong("123456789"),     // 操作哈希（用于校验）
    "v": 2,                           // Oplog 版本
    "op": "i",                        // 操作类型：i=insert, u=update, d=delete, c=command, n=noop
    "ns": "demo.users",               // 命名空间（数据库.集合）
    "o": { "_id": ObjectId(...), "name": "Alice", "age": 30 },  // 操作内容
    "o2": { "_id": ObjectId(...) }    // 更新时的查询条件（仅 update）
  }
  ```
- 操作类型示例：
  - `"op": "i"`：插入文档，`o` 为完整文档。
  - `"op": "u"`：更新文档，`o` 为修改操作符（如 `{$set: {age: 31}}`），`o2` 为 `_id` 条件。
  - `"op": "d"`：删除文档，`o` 为 `_id`。
  - `"op": "c"`：执行命令（如 `dropDatabase`, `createIndex`）。

**复制流程**：
1. **Primary 写入**：客户端写操作在 Primary 上执行，同时生成 oplog 条目追加到 `oplog.rs`。
2. **Secondary 拉取**：每个 Secondary 维护一个游标（tailable cursor）持续拉取 Primary 的 oplog。
3. **幂等应用**：Secondary 按顺序重放 oplog 操作到自己的数据集，oplog 操作设计为幂等（可重复执行）。
4. **并行复制**：MongoDB 4.0+ 支持多线程并行应用 oplog，按文档 `_id` 哈希分配到不同线程以提高吞吐。
5. **级联复制**：Secondary 可从其他 Secondary 复制（chaining），减少 Primary 负载，但增加延迟层级。

**Oplog 大小与管理**：
- 固定大小（如 5GB），满后循环覆盖最旧记录。
- 必须足够大以覆盖运维窗口（如备份、网络中断），否则 Secondary 可能因无法追溯而需要全量重同步。
- 查看 oplog 状态：`rs.printReplicationInfo()` 显示 oplog 时间窗口。

#### 6.1.3 选举机制

**选举触发条件**：
1. **初始化副本集**：首次启动时选举 Primary。
2. **Primary 不可达**：Secondary 连续 `electionTimeoutMillis`（默认 10 秒）收不到 Primary 心跳。
3. **手动触发**：执行 `rs.stepDown()` 让 Primary 主动降级，或通过 `rs.reconfig()` 修改配置。
4. **优先级变更**：高优先级节点加入后可能触发选举以替换低优先级 Primary。
5. **网络分区**：Primary 与多数节点失联后自动降级为 Secondary。

**选举过程（Raft-like 协议）**：
1. **检测故障**：Secondary 心跳超时后进入 `SECONDARY` → `ELECTION` 状态。
2. **Term 递增**：候选节点将自己的 Term（任期编号）加 1，开始新一轮选举。
3. **投票请求**：候选节点向所有节点发送 `replSetRequestVotes` 请求，包含：
   - 自己的 Term 编号。
   - 自己的最后 oplog 条目时间戳（用于比较数据新旧）。
4. **投票规则**：节点收到投票请求后，满足以下条件才投赞成票：
   - 候选节点的 Term ≥ 自己的 Term。
   - 候选节点的 oplog 至少与自己一样新（比较 `ts` 时间戳）。
   - 该 Term 内尚未投票给其他节点（每个 Term 只能投一票）。
   - 候选节点优先级 > 0（`priority: 0` 的节点不能成为 Primary）。
5. **获得多数票**：候选节点收到 **超过半数**（majority）节点的赞成票后成为 Primary。
6. **广播身份**：新 Primary 向所有节点发送心跳，宣告自己的 Primary 身份和新 Term。
7. **其他节点降级**：其他节点收到更高 Term 的 Primary 心跳后，降级为 Secondary 并同步其 oplog。

**选举超时与优化**：
- `electionTimeoutMillis`（10 秒）：心跳超时后等待时间，随机抖动避免同时发起选举。
- `heartbeatIntervalMillis`（2 秒）：心跳间隔，低延迟网络可调低以加快故障检测。
- 优先级 `priority`：0-1000，高优先级节点更容易当选（`priority: 0` 永不当选，用于冷备）。

## 6. 选举超时设置

在 MongoDB 的副本集中，`electionTimeoutMillis` 和 `heartbeatIntervalMillis` 都与选举过程相关。

- `electionTimeoutMillis` 控制选举开始的超时时间。如果在此时间内没有收到来自主节点的心跳信号，节点将开始选举过程。
- `heartbeatIntervalMillis` 则是节点之间发送心跳信号的间隔时间，确保节点之间的连接状态。

因此，`electionTimeoutMillis` 是触发选举过程的超时设置。

#### 6.1.4 防止脑裂机制

**核心策略：多数派原则（Majority Quorum）**
- **写入确认**：`writeConcern: { w: "majority" }` 要求写入被复制到 **多数节点**（> N/2）才确认成功。
- **选举投票**：候选节点必须获得 **多数节点** 的选票才能成为 Primary。
- **数学保证**：任意两个多数集合必有交集，因此不可能同时存在两个 Primary 各自获得多数支持。

**网络分区场景**：
假设 3 节点副本集（P=Primary, S1, S2）发生分区：
- **场景 1：P 与 S1 在一侧，S2 隔离**
  - P 仍能联系到多数节点（P + S1 = 2/3），继续服务。
  - S2 无法获得多数票，不会发起成功的选举。
- **场景 2：P 隔离，S1 与 S2 在一侧**
  - S1 和 S2 构成多数（2/3），可选举出新 Primary（如 S1）。
  - 旧 Primary（P）检测到无法联系多数节点，**自动降级为 Secondary**，拒绝新写入。
  - 分区恢复后，P 作为 Secondary 同步新 Primary 的 oplog，冲突的写入会被回滚。

**防止脑裂的关键机制**：
1. **Primary 自检**：Primary 持续心跳检测，若无法联系多数节点（如网络分区），主动降级（`stepDown`）。
2. **Term 单调递增**：每次选举 Term 加 1，旧 Primary 收到更高 Term 的心跳后立即降级。
3. **投票互斥**：每个节点在同一 Term 只能投一票，防止多个候选节点同时当选。
4. **`majority` writeConcern**：确保写入已复制到多数节点，分区后少数派的未确认写入会被回滚。

**回滚处理**：
- 分区期间，少数派 Primary 的写入（未达到 `w: majority`）在分区恢复后会被回滚。
- 回滚的操作存储在 `rollback/` 目录，需要人工介入恢复或丢弃（4.0+ 自动重放兼容的回滚数据）。

#### 6.1.5 读写一致性保证

**writeConcern 参数**：
- `w: 1`（默认）：写入 Primary 即返回，风险：Primary 宕机可能丢数据。
- `w: "majority"`：写入多数节点才返回，**推荐生产环境**，防止回滚。
- `j: true`：写入 journal 日志后才返回，增强持久性。
- `wtimeout`：超时时间（毫秒），避免无限等待。

**readConcern 参数**：
- `"local"`（默认）：读取本地最新数据，可能读到未提交到多数的数据（后续可能回滚）。
- `"majority"`：仅读取已复制到多数节点的数据，**推荐生产环境**，避免读到脏数据。
- `"linearizable"`：强一致性读，读取时刻最新的 majority 提交数据，性能开销大。
- `"snapshot"`：事务专用，隔离级别保证事务内一致性快照。

**因果一致性**：
- 通过 session 追踪操作的逻辑时钟（`operationTime`），确保同一 session 内后续读能看到之前写的结果。
- 即使读从 Secondary，也能保证读到至少与前次操作同步的数据。

#### 6.1.6 运维监控与优化

**关键监控指标**：
```javascript
// 查看副本集状态
rs.status();
// 关注：state（PRIMARY/SECONDARY）、health、optime、lag

// 查看 oplog 窗口
rs.printReplicationInfo();
// 输出：configured oplog size、log length start to end、oplog first event time、oplog last event time

// 查看复制延迟
rs.printSlaveReplicationInfo();
// 输出：source、syncedTo、X secs (X hrs) behind the primary
```

**性能优化建议**：
- **oplog 大小**：生产环境建议 ≥ 24 小时写入量，使用 `db.adminCommand({replSetResizeOplog: 1, size: 10240})` 在线调整。
- **索引一致性**：确保所有节点有相同索引，否则 Secondary 重放 oplog 可能变慢。
- **禁用级联复制**：高延迟场景下禁用 `chainingAllowed: false`，强制 Secondary 从 Primary 复制。
- **流控配置**：`flowControlTargetLagSeconds` 控制 Secondary 最大延迟，超出时 Primary 限速写入。
- **压缩传输**：4.2+ 支持 oplog 网络传输压缩（`networkCompression`），节省跨机房带宽。

### 6.2 分片 (Sharding)
- **目标与架构**：面向水平扩展，组件包含 Config Server（存元数据、Chunk 分布）、Mongos（查询路由）、Shard（通常是副本集，兼顾 HA）。
- **分片键选择**：
  - 高基数、写入/查询分布均匀，避免热点；时间序列常用哈希键（如 `hashed` 时间戳）消除单点热点。
  - 需要支持主要查询/排序维度，避免路由层广播查询；范围查询多用范围分片，均衡高写入可用哈希分片。
- **Chunk 管理**：默认 64MB（可调）；自动 split 生成新 Chunk，Balancer 基于统计在低峰时迁移 Chunk 保持均衡。热点键可开启 autoSplit + 哈希键降低迁移压力。
- **路由与一致性**：查询先在 Mongos 基于分片键路由；缺少分片键会广播所有 Shard，性能显著下降。写入遵循分片键唯一性；分布式事务在分片集群上依赖两阶段提交与 `snapshot` 读关注。

#### 6.2.0 范围分片 vs 哈希分片（节点分配方式）
- **谁决定落在哪个节点？** 配置完成后由集群自动分配。管理员只定义分片键类型（range/hashed）与初始 chunk，实际 chunk → shard 的映射由配置服务器记录，均衡器（Balancer）根据数据量和 chunk 统计自动迁移。
- **范围分片 (Range)**：按键的有序区间切分 chunk，每个 chunk 对应一个键区间并映射到某个 shard。热点写入集中在最新区间时，Balancer 会在低峰期切分并迁移到其他 shard，但瞬时热点仍可能压在单一 shard。
- **哈希分片 (Hashed)**：先对分片键取哈希，再按哈希空间均匀切分 chunk，天然将顺序写打散到多个 shard，避免单点热点。chunk 仍由集群自动映射到 shard，Balancer 依据哈希区间的 chunk 数量与数据量做迁移。
- **手工控制**：可用 `sh.moveChunk` 将特定区间/哈希段迁移到指定 shard，或通过 Tag Range/Zone 将某些键范围绑定到特定机房/节点组（常用于合规或地域亲和）。
- **元数据存放**：Config Server 存储 chunk 边界与所属 shard。Mongos 只读缓存元数据并按分片键路由；数据节点不自行决定路由。

#### 6.2.1 哈希键分片下的读取流程（按步骤）
1) **客户端发起命令**：应用通过驱动发送查询（建议包含分片键或可推导的过滤条件，避免广播）。
2) **Mongos 解析与路由决策**：
  - 解析查询条件和集合元数据，检查是否带分片键字段。
  - 查询 Config Server 缓存的 Chunk 映射（若缓存陈旧则刷新）以确定哈希区间 → 目标分片列表。
  - 若缺分片键且无法推导，Mongos 会对所有分片广播查询（scatter-gather）。
3) **请求下发到分片副本集**：
  - Mongos 将请求发给目标分片的 `readPreference` 命中的节点（默认 Primary，可配置 Secondary）。
  - 分片内部仍是副本集，读一致性由 `readConcern` 决定（如 `majority`）。
4) **Shard 执行与过滤**：目标分片在对应节点执行查询，使用本地索引过滤并生成结果。缺分片键的广播场景下，每个分片独立执行并返回部分结果。
5) **Mongos 合并与排序**：
  - Mongos 收集各分片返回的结果流，按需要做排序、限制、投影和去重。
  - 对分页/排序查询，Mongos 可能执行分布式游标，分片侧返回分批结果，Mongos 负责聚合。
6) **结果返回客户端**：合并后的结果集通过驱动返回应用；若使用游标，则按批次（batch/limit）继续从 Mongos 拉取。

**注意**：
- 哈希分片读路径仍依赖分片键定位 Chunk；未携带分片键会退化为广播，延迟和网络开销显著增加。
- 路由决策基于 Config Server 元数据缓存，Balancer 迁移 Chunk 时 Mongos 会在短暂窗口内刷新缓存以避免错路由。
- 读一致性由 `readConcern` 决定；跨分片的强一致读需结合 `majority` 或事务。

#### 6.2.2 Balancer 迁移 Chunk 原理与流程
**目标**：均衡各 Shard 的 chunk 数量和数据量，避免单点热点与存储倾斜。

**何时触发**：
- 定时后台线程在 Config Server 上运行，默认低峰期更活跃；手动 `balancerStart/Stop` 控制开关。
- 监测 shard 间 chunk 数差异超阈值（`balancer` 配置中的 imbalance threshold）；达到阈值则计划迁移。
- 写入热点导致新 chunk split 后局部不均衡，也会触发迁移。

**迁移步骤（per chunk）**：
1) **选择 chunk**：Balancer 选择 chunk 较多/容量较大的源 shard，挑选一个 chunk 迁往 chunk 较少的目标 shard。
2) **校验与锁**：在 Config Server 上对相关元数据加分布式锁，确保迁移期间 chunk 元数据一致；验证目标 shard 可用且无冲突迁移。
3) **数据复制阶段**：源 shard 启动 `moveChunk`，在目标 shard 创建接收集合并增量复制该 chunk 的文档（基于分片键范围或哈希区间）到目标；复制期间源继续接受写入。
4) **Catch-up 阶段**：持续同步源上的新写入（针对该 chunk），直到增量差异收敛。
5) **Critical Section（短暂写暂停）**：对该 chunk 的写入短暂加锁，切换 Config Server 上的 chunk 所属 shard 元数据（源→目标），确保路由一致。
6) **清理源数据**：切换完成后，源 shard 删除旧 chunk 数据，释放存储。
7) **缓存刷新**：Mongos 收到元数据变更事件后刷新路由缓存，避免错路由；旧缓存会因刷新或 TTL 失效。

**关键参数/命令**：
- 查看/控制：`sh.getBalancerState()`，`sh.stopBalancer()`，`sh.startBalancer()`，`sh.isBalancerRunning()`。
- 迁移阈值：`settings` 集合中的 `balancer` 文档；可配置 chunk 大小、均衡策略、并发度。
- 手工迁移：`sh.moveChunk("db.coll", { key: value }, "shardName")`；可与 Tag Range/Zone 配合实现地域/合规放置。

**运维提示**：
- 迁移会占用网络和磁盘 IO，建议在业务低峰执行；可配置维护窗口。
- 与长事务/大批量写入叠加时可能放大锁等待，注意监控锁与 oplog 延迟。
- 如需暂停均衡（例如批量导入或大规模 DDL），先 `sh.stopBalancer()`，完成后再开启。
- **路由缓存未刷新时的处理**：迁移完成后若 Mongos 仍持旧路由，可能将请求发到源 shard。源 shard 会返回 `StaleConfig`/`StaleShardVersion`，Mongos 随即刷新 Config Server 元数据并重试，随后请求会路由到新 shard。

### 6.3 索引原理
- **结构与能力**：默认 B-Tree，支持前缀匹配、范围、排序；复合索引遵循最左前缀，`$eq`/`$in`/`$lt`/`$gt` 组合可利用索引。
- **类型与特性**：
  - 唯一索引、部分索引（`partialFilterExpression`）、稀疏索引（仅存在字段）、TTL 索引（定期过期），Wildcard 索引（半结构化场景）。
  - 覆盖查询：命中索引且查询字段全在索引中，无需回表；`explain("executionStats")` 检查 `IXSCAN` / `FETCH`。
- **成本与权衡**：索引加速读，但增加写放大与存储；每次写入需要维护相关索引，更新高频字段应谨慎建索引。Collation 会影响索引可复用性。

### 6.4 存储与一致性
- **WiredTiger 机制**：文档级锁提升并发；采用写前日志 (journal) + checkpoint 持久化，默认 Snappy 压缩，数据/索引页支持压缩与缓存调优 (`wiredTigerCacheSizeGB`)。
- **一致性模型**：
  - `writeConcern` 决定写入持久性；`readConcern` 决定读到的数据可见性（`majority` 防止读到回滚数据）。
  - 会话因果一致性保证同一会话内操作顺序；事务在副本集/分片上使用 `snapshot` 级别实现跨集合、跨分片多文档原子性。
- **回滚与恢复**：Primary 与 Majority 失联时可能回滚未提交到多数的写；重启依赖 journal + checkpoint 快速恢复。

#### 6.4.1 WiredTiger Checkpoint 机制
- **作用**：将内存中的脏页和已有 journal 中的已持久化操作，落盘形成一致性快照。重启时可从最近的 checkpoint 加上后续 journal 重放恢复。
- **触发方式**：默认约 60 秒一次（`wiredTigerCheckpointInterval`），或达到一定脏页/日志量时触发；也可通过 `fsyncLock`/`fsyncUnlock` 间接控制维护窗口。
- **流程概览**：
  1) 冻结 checkpoint 开始时刻的写视图，继续接受新写但新写落在下一代日志里。
  2) 将需要刷新的脏页写入数据文件，记录新的 metadata（LSN）指向该一致性点。
  3) 完成后更新 checkpoint 元数据，旧的 checkpoint 记录可被清理（配合 `wiredTigerEngineRuntimeConfig` 中的历史表设置）。
- **与 journal 的关系**：journal 提供崩溃恢复的 write-ahead 保障，checkpoint 提供数据文件的定期一致性点。恢复时先加载 checkpoint 数据，再重放 checkpoint 之后的 journal 条目。
- **调优要点**：
  - 更短间隔提升崩溃后重放速度，但增加 IO；更长间隔减少 IO 但恢复需重放更多日志。
  - 监控脏页比例、cache 命中率与后台写入压力，必要时调整 `wiredTigerCacheSizeGB`、checkpoint 间隔或磁盘性能。
  - 大量突发写入时，checkpoint 可能与 journal/fsync 叠加放大写放大，观察磁盘队列和写延迟，必要时分时段导入或限流。

## 7. MongoDB 集群架构

MongoDB 集群通常由一个主节点和多个从节点组成。大厂通用的配置是一个主节点带有两个到五个从节点。一个副本集可以有多个主从副本集，通常建议在生产环境中使用三个副本集，以确保高可用性和数据冗余。

在 MongoDB 中，添加的文档会根据分片键（shard key）存放在特定的节点中。MongoDB 使用哈希或范围分片策略来决定文档存放的位置。通过查询 `_id` 或其他分片键，可以确认文档存放在哪个节点中。

## 8. 常用管理命令（副本集 / 分片）

```javascript
// 查看副本集状态（在 Primary 上）
rs.status();

// 初始化副本集（示例）
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "192.168.31.140:27017" },
    { _id: 1, host: "192.168.31.141:27017" },
    { _id: 2, host: "192.168.31.142:27017", arbiterOnly: true }
  ]
});

// 查看当前分片状态（在 mongos 上）
sh.status();

// 启用数据库分片
sh.enableSharding("demo");

// 为集合选择分片键并分片（哈希示例）
sh.shardCollection("demo.users", { userId: "hashed" });
```

## 9. 性能与运维建议
- 为高频查询建立合适的复合索引，避免全表扫描。
- 定期使用 `explain()` 检查慢查询并优化索引。
- 控制索引数量，避免写入放大和存储膨胀。
- 备份与恢复：使用 `mongodump` / `mongorestore` 或基于快照的备份方案。
- 监控关键指标：复制延迟、oplog 大小、连接数、内存命中率、锁等待、慢查询日志。
- 生产环境开启认证与 TLS，限制网络访问，使用最小权限账户。

## 10. 快速命令清单

```bash
# 本地连接
mongosh --host 192.168.31.140 --port 27017

# 插入 / 查询 / 更新 / 删除（示例在 demo.users）
mongosh --eval "db.getSiblingDB('demo').users.insertOne({name:'Alice',age:30})"
mongosh --eval "db.getSiblingDB('demo').users.find({name:'Alice'}).pretty()"
mongosh --eval "db.getSiblingDB('demo').users.updateOne({name:'Alice'},{$set:{age:31}})"
mongosh --eval "db.getSiblingDB('demo').users.deleteOne({name:'Alice'})"

# 创建索引
mongosh --eval "db.getSiblingDB('demo').users.createIndex({city:1,age:-1})"

# 查看索引与统计
mongosh --eval "db.getSiblingDB('demo').users.getIndexes()"
mongosh --eval "db.getSiblingDB('demo').users.find({city:'Beijing'}).sort({age:-1}).explain('executionStats')"
```
