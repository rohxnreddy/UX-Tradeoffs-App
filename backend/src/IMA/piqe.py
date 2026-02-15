import cv2
import torch
import pyiqa


# load PIQE metric once
_device = "cpu"
_piqe = pyiqa.create_metric("piqe", device=_device)


def piqe_score(image_path):
    """
    Compute PIQE score from an image path.
    Lower score = better image quality.
    """
    img = cv2.imread(image_path)

    if img is None:
        raise Exception("Image not found")

    # pyiqa expects RGB tensor
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # convert to tensor (C,H,W) and normalize to [0,1]
    tensor = torch.from_numpy(img).float() / 255.0
    tensor = tensor.permute(2, 0, 1).unsqueeze(0)

    score = _piqe(tensor)

    return float(score.item())