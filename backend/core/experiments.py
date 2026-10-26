"""Deterministic A/B experiments.

Assignment is a hash of the experiment name + user id, so a user always sees the
same variant and no assignment table is needed. Weights are percentages.
"""
import hashlib

EXPERIMENTS = {
    'ranking_v2': {'variants': ('A', 'B'), 'weights': (50, 50)},
    'notification_copy': {'variants': ('A', 'B'), 'weights': (50, 50)},
}

RANKING_WEIGHTS = {
    'A': {
        'sport': 0.40,
        'city': 0.20,
        'urgency': 0.15,
        'scarcity': 0.10,
        'social': 0.10,
        'quality': 0.05,
        'exploration': 0.10,
    },
    'B': {
        'sport': 0.33,
        'city': 0.15,
        'urgency': 0.12,
        'scarcity': 0.08,
        'social': 0.22,
        'quality': 0.10,
        'exploration': 0.18,
    },
}


def _bucket(user, name):
    if not getattr(user, 'id', None):
        return 0
    digest = hashlib.sha256(f'{name}:{user.id}'.encode('utf-8')).digest()
    return int.from_bytes(digest[:8], 'big') % 100


def variant_for(user, name, variants=('A', 'B'), weights=None):
    variants = tuple(variants)
    if not variants:
        return ''
    if weights is None:
        config = EXPERIMENTS.get(name)
        if config:
            variants = config['variants']
            weights = config['weights']
    if not weights or len(weights) != len(variants):
        weights = tuple(1 for _ in variants)
    bucket = _bucket(user, name)
    cursor = 0
    for variant, weight in zip(variants, weights):
        cursor += weight
        if bucket < cursor:
            return variant
    return variants[-1]


def ranking_config(user):
    variant = variant_for(user, 'ranking_v2')
    return {'variant': variant, **RANKING_WEIGHTS.get(variant, RANKING_WEIGHTS['A'])}


def experiment_payload(user):
    return {name: variant_for(user, name) for name in EXPERIMENTS}
