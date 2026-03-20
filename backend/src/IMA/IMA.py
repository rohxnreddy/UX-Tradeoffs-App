from concurrent.futures import ThreadPoolExecutor
from .brIsque import brisque_score
from .niqe import niqe_score
from .piqe import piqe_score
# from .rankiqa import rankiqa_score
# from .metaiqa import metaiqa_score



def compute_iqa(image_path):
    """
    Runs all IQA metrics on an image in parallel threads and returns results.
    """

    with ThreadPoolExecutor(max_workers=3) as executor:
        future_brisque = executor.submit(brisque_score, image_path)
        future_niqe    = executor.submit(niqe_score, image_path)
        future_piqe    = executor.submit(piqe_score, image_path)

        results = {
            "brisque": future_brisque.result(),
            "niqe": future_niqe.result(),
            "piqe": future_piqe.result(),
        }

    return results


# if __name__ == "__main__":
#     path = "filepath/to/your/image.jpg"

#     scores = compute_iqa(path)
#     print(scores)