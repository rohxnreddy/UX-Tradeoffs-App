import cv2
import torch
import pyiqa

# load model once
_device = "cpu"
_metaiqa = pyiqa.create_metric("metaiqa", device=_device)


def metaiqa_score(image_path):
    """
    Compute MetaIQA score from image path.
    Higher score = better perceptual quality (MOS-like).
    """
    img = cv2.imread(image_path)

    if img is None:
        raise Exception("Image not found")

    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    tensor = torch.from_numpy(img).float() / 255.0
    tensor = tensor.permute(2, 0, 1).unsqueeze(0)

    score = _metaiqa(tensor)

    return float(score.item())