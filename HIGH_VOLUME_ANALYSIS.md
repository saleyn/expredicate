# ATree Expression Engine: High-Volume Evaluation Analysis

## Scenario: Insert Once, Evaluate Millions of Times

This analysis covers a critically different use case from the typical ATree workflow.

### Problem Statement

**Key Assumption Change**:
- Rules are inserted once (one-time cost, amortized to near-zero)
- Rules are evaluated millions of times at high velocity
- **Evaluation performance becomes the dominant factor**

**Real-World Examples**:
- Continuous event stream processing (IoT, logs, market data)
- High-throughput request routing (millions/sec)
- Stream processing with rule-based filtering
- Real-time analytics over time-series data

---

## Performance Impact Analysis

### Scenario: 10,000 Rules, 1,000,000 Evaluations

**Custom Recursive Descent Parser**:

```
Rules: 10,000
Evaluations: 1,000,000
Per-rule eval time: 1.24 μs
Total evaluation time: 10,000 × 1.24 μs × 1,000,000 = 12,400,000,000 μs = 12.4 seconds
Per-second throughput: ~806 K evaluations/sec
```

**Bytecode Virtual Machine**:

```
Rules: 10,000
Evaluations: 1,000,000
Per-rule eval time: 0.95 μs (23% faster)
Total evaluation time: 10,000 × 0.95 μs × 1,000,000 = 9,500,000,000 μs = 9.5 seconds
Per-second throughput: ~1.05 M evaluations/sec
```

**Time Savings**:
```
Difference: 12.4s - 9.5s = 2.9 seconds per million evaluations
Percentage: ~23% faster evaluation
For 10 million evaluations: 29 seconds saved
For 100 million evaluations: 290 seconds (4+ minutes) saved
```

---

## Payoff Analysis

### Does Bytecode Justify Its Complexity?

**Added Complexity Costs**:
- 200 more lines of code to maintain
- More intricate evaluation logic (stack-based VM)
- Harder to debug bytecode issues
- Additional instruction generation overhead

**Performance Payoff**:

| Scenario | Duration | Bytecode Savings | Worth It? |
|----------|----------|------------------|-----------|
| 1M evals | 12.4s | 2.9s | Marginal |
| 10M evals | 124s | 29s | Yes |
| 100M evals | 1,240s | 290s | Definitely Yes |
| 1B evals | 12,400s | 2,900s | Absolutely Yes |

**Break-Even Analysis**:
- Break-even is approximately **5-10 million evaluations**
- Above this threshold: bytecode VM is worth the complexity
- Below this threshold: custom parser's simplicity wins

---

## How to Detect and Switch

### Hybrid Approach: Adaptive Engine Selection

```cpp
class AdaptiveExpressionEngine {
  // Insert-time decision
  size_t estimated_eval_count;  // User provides hint or we estimate
  
  if (estimated_eval_count > 10_000_000) {
    // High-volume: Use bytecode
    use_bytecode_engine();
  } else {
    // Typical load: Use custom parser
    use_custom_parser();
  }
};
```

### Runtime Selection Heuristics

**Option 1: Explicit Configuration**
```elixir
ATree.new(mode: :bytecode)  # For high-volume workloads
ATree.new(mode: :parser)    # Default, for typical workloads
ATree.new()                 # Auto-detect based on usage
```

**Option 2: Auto-Detection**
```cpp
// Start with custom parser (simpler)
// After N evaluations, measure performance
// If evaluation rate is high, switch to bytecode
if (evaluation_count > 100_000 && 
    avg_query_time_exceeds_threshold) {
  migrate_to_bytecode_engine();
}
```

**Option 3: Rules-Based Switch**
```cpp
// User hints via NIF options
{:eval_heavy => true}   // Use bytecode from start
{:eval_light => true}   # Keep custom parser
```

---

## Revised Recommendation

### For Typical ATree Use Cases (Insert-Once, Evaluate-Once)
✅ **Keep custom parser** (11% faster overall)

### For High-Volume Streaming/Evaluation Workloads
✅ **Use bytecode engine** (23% faster evaluation)

### For Production ATree

**Recommended Strategy**:

1. **Default to Custom Parser**
   - Better code simplicity
   - Sufficient for most use cases
   - Easy to understand and maintain

2. **Add Bytecode Support**
   - Implement `atree_bytecode.h` (already done ✓)
   - Add NIF option: `eval_engine: :bytecode`
   - Minimal overhead to support both

3. **Documentation**
   - Document when to use each engine
   - Provide performance guidance
   - Include threshold analysis

4. **Future Optimization**
   - Monitor real-world usage patterns
   - Implement auto-detection if feasible
   - Profile production workloads

---

## Actual ATree Use Case Assessment

**Question**: Is ATree's typical usage "insert once, evaluate millions" or something else?

Looking at the module design:
- `RuleTree.match/2` - matches ONE value map
- Called per-query or per-request, not in tight loops
- Typical pattern: "given this user, which rules match?"

**If used as**: "Filter 1 million events through 10K rules"
- Then bytecode **IS worth it**
- Query time drops from 12.4s to 9.5s
- Processing 10M events/sec becomes 1M → 806K/sec

**If used as**: "Answer 100K queries with 100 rules each"
- Then custom parser **IS better overall**
- Insert: 235 μs (negligible)
- 100K queries with 100 rules: ~124ms custom vs 95ms bytecode
- Bytecode saves ~29ms, but simpler codebase wins

---

## Implementation Guidance

If implementing both engines for production:

### Build Configuration
```makefile
# Support both implementations
ifeq ($(EVAL_ENGINE), bytecode)
  CPPFLAGS += -DATREE_USE_BYTECODE
else
  # Default to custom parser
  CPPFLAGS += -DATREE_USE_PARSER
endif
```

### Runtime Selection
```cpp
#ifdef ATREE_USE_BYTECODE
  using RuleEngineT = RuleTreeBytecode;
#else
  using RuleEngineT = RuleTree;
#endif
```

### NIF Interface
```c
// Add engine selection to atree_nif.cpp
ERL_NIF_TERM atree_new_with_engine(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
  const char* engine = get_engine_option(argv[0]);
  
  if (strcmp(engine, "bytecode") == 0) {
    // Create bytecode engine
  } else {
    // Create custom parser (default)
  }
}
```

---

## Conclusion

### The Work That's Already Done

✅ Evaluation documents created:
- `EXPRTK_EVALUATION.md` - ExprTK vs custom comparison
- `PERFORMANCE_ANALYSIS.md` - Bytecode vs custom analysis

✅ Full implementations available:
- `c_src/atree.h` - Current custom parser (600 LOC, proven)
- `c_src/atree_bytecode.h` - Alternative bytecode engine (800 LOC, optimized)
- `c_src/benchmark.cpp` - Comprehensive benchmarks

### The Decision Trees

**Should I use the custom parser?**
- Default: YES ✅
- Expected evals: < 10M per day
- Need simplicity and maintainability
- Typical query-response patterns
- → Use custom parser

**Should I use the bytecode engine?**
- Streaming/high-volume evaluation: YES ✅
- Expected evals: > 10M per second
- Acceptable additional complexity
- Rule latency is critical
- → Use bytecode engine

**Should I implement both?**
- Yes, if supporting diverse use cases
- Most production systems should default to parser
- Offer bytecode as option for power users
- This requires NIF modifications (non-trivial)

### Actual Production Recommendation

**For current ATree** (without knowing exact usage):
- Keep custom parser as default
- Document that bytecode alternative exists in codebase
- If users report evaluation bottlenecks, benchmark their workload
- Add bytecode support only if real-world demand exists

This balanced approach:
- ✅ Optimizes the most common case (simpler, fastest overall)
- ✅ Provides solution for high-volume scenarios (bytecode alternative ready)
- ✅ Avoids premature optimization (don't ship unused code)
- ✅ Maintains code simplicity (easier to audit and maintain)
