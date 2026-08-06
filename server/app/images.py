import io
import warnings
from dataclasses import dataclass

from PIL import Image, ImageOps, UnidentifiedImageError


@dataclass(frozen=True)
class NormalizedImage:
    data: bytes
    mime_type: str = "image/jpeg"


class InvalidImageError(ValueError):
    pass


def normalize_image(image_bytes: bytes, *, max_dimension: int) -> NormalizedImage:
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(image_bytes)) as probe:
                image_format = probe.format
                width, height = probe.size
                if image_format not in {"JPEG", "PNG"}:
                    raise InvalidImageError("Only JPEG and PNG images are supported.")
                if width < 8 or height < 8:
                    raise InvalidImageError("Image is too small.")
                if width > max_dimension or height > max_dimension:
                    raise InvalidImageError("Image dimensions are too large.")
                probe.verify()

            with Image.open(io.BytesIO(image_bytes)) as decoded:
                decoded = ImageOps.exif_transpose(decoded)
                decoded.load()
                rgb = _to_rgb(decoded)
                output = io.BytesIO()
                rgb.save(output, format="JPEG", quality=85, optimize=True)
                return NormalizedImage(output.getvalue())
    except InvalidImageError:
        raise
    except (Image.DecompressionBombError, Image.DecompressionBombWarning) as error:
        raise InvalidImageError("Image dimensions are too large.") from error
    except (UnidentifiedImageError, OSError, ValueError) as error:
        raise InvalidImageError("Invalid image.") from error


def _to_rgb(image: Image.Image) -> Image.Image:
    if image.mode in {"RGBA", "LA"}:
        rgba = image.convert("RGBA")
        background = Image.new("RGB", rgba.size, "white")
        background.paste(rgba, mask=rgba.getchannel("A"))
        return background
    return image.convert("RGB")
