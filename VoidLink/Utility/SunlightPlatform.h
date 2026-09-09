#pragma once

#include <stdbool.h>
#include <stdatomic.h>

// App lifecycle policy is shared by the UI and streaming callbacks, not the
// transport library. Atomic access keeps background transitions race-free.
extern atomic_bool appDidEnterBackgroundWithoutPip;
