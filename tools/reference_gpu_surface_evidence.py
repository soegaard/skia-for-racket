"""Validate selected-backend surface acceptance receipts, never fabricate them."""
from reference_support import need

COMMON_CASES = (
    'native target metadata and exact opaque pixels agree',
    'snapshot owns captured contents after surface mutation and closure',
    'upload survives closure of its CPU source',
    'same-context image reuse returns an independent wrapper',
    'another context cannot consume a GPU image implicitly',
    'integer GPU subsets keep the selected source pixels',
    'filter result geometry supplies a contained subset and offset',
    'typed readback writes pixels but preserves row padding',
    'tagged-to-untagged typed readback fails without destination mutation',
    'destination dimensions are checked before writing',
    'snapshots readback and targeted flush reject unbalanced stacks',
    'typed CPU image remains usable after the GPU context is closed',
    'targeted flush requests no readback submission or completion',
    'cache operations retain a usable context and restore its byte limit',
    'bounded GPU memory report has a context scope and detached entries',
    'format queries distinguish support from an allocated sample count',
    'opaque background and conflicting alpha requests are rejected',
    'actual displayed helpers render and place their pixels',
)
ONE_SHOT_CASE = 'one-shot owned-backend rendering calls once and returns a CPU image'


def check_gpu_surface_receipt(receipt, backend, adapter):
    need(backend in ('opengl', 'metal', 'direct3d'), 'unknown surface backend')
    expected = set(COMMON_CASES)
    if backend != 'opengl':
        expected.add(ONE_SHOT_CASE)
    need(receipt.get('schema') == 1 and receipt.get('status') == 'passed',
         'GPU surface acceptance did not pass')
    need(receipt.get('backend') == backend and receipt.get('adapter') ==
         (adapter if backend == 'direct3d' else False), 'GPU surface backend/adapter mismatch')
    names = receipt.get('case_names')
    need(isinstance(names, list) and all(isinstance(name, str) for name in names)
         and set(names) == expected and len(names) == len(expected),
         'GPU surface case inventory is incomplete or duplicated')
    need(type(receipt.get('tests_run')) is int and receipt['tests_run'] == len(expected)
         and type(receipt.get('failures')) is int and receipt['failures'] == 0,
         'GPU surface test count or failures disagree')
    created = receipt.get('managed_contexts_created')
    need(type(created) is int and created > 0
         and type(receipt.get('managed_contexts_closed')) is int
         and receipt['managed_contexts_closed'] == created
         and receipt.get('context_states') == ['closed'] * created,
         'GPU surface context closure is incomplete')
    for key in ('pixel_probes_checked', 'readbacks_completed'):
        need(type(receipt.get(key)) is int and receipt[key] > 0,
             'GPU surface acceptance has no completed ' + key)
    one_shot = backend != 'opengl'
    need(type(receipt.get('one_shot_successes')) is int
         and receipt['one_shot_successes'] == int(one_shot)
         and receipt.get('one_shot_native_status') ==
         ('passed' if one_shot else 'not-run-external-host-required'),
         'one-shot coverage does not match the selected host route')
    for key in ('float_allocation_tested', 'presentation_tested', 'hardware_acceleration_verified'):
        need(receipt.get(key) is False, 'surface receipt overstates its validation scope: ' + key)
    return receipt
