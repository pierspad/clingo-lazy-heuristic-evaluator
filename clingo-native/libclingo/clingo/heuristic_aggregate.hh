#pragma once

#include <map>
#include <memory>
#include <string>

struct AggregateState {
    virtual ~AggregateState() = default;
    virtual void add(int value) = 0;
    virtual void remove(int value) = 0;
    virtual int result() const = 0;
    virtual void reset() = 0;
};

struct SumState final : AggregateState {
    int total = 0;
    void add(int v) override { total += v; }
    void remove(int v) override { total -= v; }
    int result() const override { return total; }
    void reset() override { total = 0; }
};

struct CountState final : AggregateState {
    int count = 0;
    void add(int) override { ++count; }
    void remove(int) override { --count; }
    int result() const override { return count; }
    void reset() override { count = 0; }
};

struct MinState final : AggregateState {
    std::map<int, int> active;

    void add(int v) override { active[v]++; }

    void remove(int v) override {
        auto it = active.find(v);
        if (it != active.end() && --(it->second) == 0) {
            active.erase(it);
        }
    }

    int result() const override {
        return active.empty() ? 0 : active.begin()->first;
    }

    void reset() override { active.clear(); }
};

struct MaxState final : AggregateState {
    std::map<int, int> active;

    void add(int v) override { active[v]++; }

    void remove(int v) override {
        auto it = active.find(v);
        if (it != active.end() && --(it->second) == 0) {
            active.erase(it);
        }
    }

    int result() const override {
        return active.empty() ? 0 : active.rbegin()->first;
    }

    void reset() override { active.clear(); }
};

inline std::unique_ptr<AggregateState> make_aggregate(std::string const &op) {
    if (op == "__sum") {
        return std::make_unique<SumState>();
    }
    if (op == "__count") {
        return std::make_unique<CountState>();
    }
    if (op == "__min") {
        return std::make_unique<MinState>();
    }
    if (op == "__max") {
        return std::make_unique<MaxState>();
    }
    return nullptr;
}
