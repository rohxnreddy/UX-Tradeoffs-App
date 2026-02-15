import sys
import numpy as np
import scipy

# compatibility fixes
scipy.ndarray = np.ndarray

from libsvm import svmutil
sys.modules['svmutil'] = svmutil

import cv2
from brisque import BRISQUE

brisque_model = BRISQUE()


def brisque_score(image_path):
    img = cv2.imread(image_path)

    if img is None:
        raise Exception("Image not found")

    return float(brisque_model.get_score(img))