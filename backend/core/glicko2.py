"""Glicko-2 rating updates.

Glicko-2 tracks both a rating and a rating deviation (RD, i.e. uncertainty).
New players start with a high RD so their rating moves quickly; settled players
move less. Volatility tracks how erratic a player's results have been.

Reference: Mark E. Glickman, "Example of the Glicko-2 system".
"""
import math

INITIAL_RATING = 1200.0
INITIAL_RD = 350.0
INITIAL_VOLATILITY = 0.06
TAU = 0.5
SCALE = 173.7178
CENTER = 1200.0
EPSILON = 1e-6
MIN_RD = 30.0
MAX_RD = 350.0


def _g(phi):
    return 1.0 / math.sqrt(1.0 + (3.0 * phi * phi) / (math.pi * math.pi))


def _expected(mu, mu_j, phi_j):
    return 1.0 / (1.0 + math.exp(-_g(phi_j) * (mu - mu_j)))


def update_rating(rating, rd, volatility, opponents, tau=TAU):
    """Return (new_rating, new_rd, new_volatility).

    ``opponents`` is an iterable of ``(opponent_rating, opponent_rd, score)``
    where score is 1.0 (win), 0.5 (draw) or 0.0 (loss). All opponents are
    treated as one rating period.
    """
    opponents = list(opponents)
    if not opponents:
        return float(rating), float(rd), float(volatility)

    mu = (float(rating) - CENTER) / SCALE
    phi = max(float(rd), EPSILON) / SCALE
    sigma = max(float(volatility), EPSILON)

    v_inv = 0.0
    delta_sum = 0.0
    for opp_rating, opp_rd, score in opponents:
        mu_j = (float(opp_rating) - CENTER) / SCALE
        phi_j = max(float(opp_rd), EPSILON) / SCALE
        g = _g(phi_j)
        e = _expected(mu, mu_j, phi_j)
        v_inv += g * g * e * (1.0 - e)
        delta_sum += g * (score - e)

    if v_inv <= 0:
        return float(rating), float(rd), float(volatility)

    v = 1.0 / v_inv
    delta = v * delta_sum

    # Solve for the new volatility with the Illinois algorithm.
    a = math.log(sigma * sigma)

    def f(x):
        ex = math.exp(x)
        return (
            (ex * (delta * delta - phi * phi - v - ex))
            / (2.0 * (phi * phi + v + ex) ** 2)
            - (x - a) / (tau * tau)
        )

    if delta * delta > phi * phi + v:
        b = math.log(delta * delta - phi * phi - v)
    else:
        k = 1
        while f(a - k * tau) < 0 and k < 100:
            k += 1
        b = a - k * tau

    fa, fb = f(a), f(b)
    for _ in range(100):
        if abs(b - a) <= EPSILON:
            break
        c = a + (a - b) * fa / (fb - fa)
        fc = f(c)
        if fc * fb <= 0:
            a, fa = b, fb
        else:
            fa /= 2.0
        b, fb = c, fc

    new_sigma = math.exp(a / 2.0)
    phi_star = math.sqrt(phi * phi + new_sigma * new_sigma)
    phi_new = 1.0 / math.sqrt(1.0 / (phi_star * phi_star) + v_inv)
    mu_new = mu + phi_new * phi_new * delta_sum

    new_rating = CENTER + SCALE * mu_new
    new_rd = min(MAX_RD, max(MIN_RD, SCALE * phi_new))
    return new_rating, new_rd, new_sigma


def display_rating(value):
    return int(round(value))
