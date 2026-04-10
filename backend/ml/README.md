# In-house face / gender model (optional)

This folder holds **your own** training + inference code — no paid third-party APIs.

## What you get

- `train_gender_cnn.py` — trains a small CNN on a folder of images organized by class (`Male/`, `Female/`, …). Suitable for datasets you download from [Kaggle](https://www.kaggle.com/) (e.g. UTKFace, CelebA subsets) after you accept their licenses.
- `infer_face_gender.py` — loads `weights.pt` (if present) and prints a JSON line with predicted label + confidence for one image path.

## Workflow

1. Create a Python 3.10+ venv and `pip install -r requirements.txt`.
2. Prepare `data/Male`, `data/Female`, `data/Transgender` (or adjust labels in the script).
3. Run `python train_gender_cnn.py --data-dir ./data --epochs 15 --out weights.pt`.
4. Copy `weights.pt` onto the server next to the scripts.
5. Wire the Node KYC route to call `python infer_face_gender.py <path>` and enforce consistency with onboarding gender (similar to existing selfie checks).

The API server does **not** run training; it only runs lightweight inference if you deploy the weights.

## Notes

- Quality depends entirely on your dataset size, balance, and augmentation — expect to iterate.
- For production, add hold-out evaluation, bias testing, and clear disclosure in product copy.
