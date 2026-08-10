def estimate_1rm(weight: float, reps: int) -> float:
    """Epley formula. Used to rank set performance for PR detection instead of
    comparing raw weight, so e.g. 100kg x 1 doesn't automatically outrank a
    heavier-effort 97.5kg x 5."""
    if reps <= 1:
        return weight
    return weight * (1 + reps / 30)
