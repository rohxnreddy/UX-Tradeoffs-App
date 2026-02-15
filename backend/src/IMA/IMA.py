from .brIsque import brisque_score
from .niqe import niqe_score
from .piqe import piqe_score
# from .rankiqa import rankiqa_score
# from .metaiqa import metaiqa_score


def compute_iqa(image_path):
    """
    Runs all IQA metrics on an image and returns results.
    """

    results = {
        "brisque": brisque_score(image_path),
        "niqe": niqe_score(image_path),
        "piqe": piqe_score(image_path),
        # "rankiqa": rankiqa_score(image_path),
        # "metaiqa": metaiqa_score(image_path),
    }

    return results


# if __name__ == "__main__":
#     path = "filepath/to/your/image.jpg"

#     scores = compute_iqa(path)
#     print(scores)