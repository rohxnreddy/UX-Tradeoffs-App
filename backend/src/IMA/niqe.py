import cv2
import torch
import pyiqa

_device = "cpu"
_niqe = pyiqa.create_metric("niqe", device=_device)


def niqe_score(image_path):
    img = cv2.imread(image_path)

    if img is None:
        raise Exception("Image not found")

    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    tensor = torch.from_numpy(img).float() / 255.0
    tensor = tensor.permute(2, 0, 1).unsqueeze(0)

    score = _niqe(tensor)
    return float(score.item())