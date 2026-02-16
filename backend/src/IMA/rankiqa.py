import torch
import pyiqa

# load model once
_device = "cuda" if torch.cuda.is_available() else "cpu"
_metric = pyiqa.create_metric("maniqa", device=_device)


def rankiqa_score(image_path):
    """
    Compute IQA score using MANIQA.
    Higher score = better quality.
    """
    score = _metric(image_path)
    return float(score.item())