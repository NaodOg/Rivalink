import math

K_FACTOR = 32
K_FACTOR_NEW = 48
NEW_PLAYER_THRESHOLD = 10
INITIAL_ELO = 1200

def expected_score(rating_a, rating_b):
    return 1.0 / (1.0 + math.pow(10, (rating_b - rating_a) / 400.0))

def k_factor(matches_played):
    if matches_played < NEW_PLAYER_THRESHOLD:
        return K_FACTOR_NEW
    return K_FACTOR

def update_elo(winner_rating, loser_rating, draw=False):
    e_winner = expected_score(winner_rating, loser_rating)
    e_loser = expected_score(loser_rating, winner_rating)

    if draw:
        s_winner = 0.5
        s_loser = 0.5
    else:
        s_winner = 1.0
        s_loser = 0.0

    new_winner = round(winner_rating + k_factor(0) * (s_winner - e_winner))
    new_loser = round(loser_rating + k_factor(0) * (s_loser - e_loser))
    return new_winner, new_loser

def update_elo_with_matches(winner_rating, loser_rating, winner_matches, loser_matches, draw=False):
    e_winner = expected_score(winner_rating, loser_rating)
    e_loser = expected_score(loser_rating, winner_rating)

    if draw:
        s_winner = 0.5
        s_loser = 0.5
    else:
        s_winner = 1.0
        s_loser = 0.0

    new_winner = round(winner_rating + k_factor(winner_matches) * (s_winner - e_winner))
    new_loser = round(loser_rating + k_factor(loser_matches) * (s_loser - e_loser))
    return new_winner, new_loser
