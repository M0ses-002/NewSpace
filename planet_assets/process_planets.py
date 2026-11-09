from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image

source_dir = Path('C:/Users/Moses02/.workbuddy/clipboard-images')
files = ['clipboard-2026-11-07T08-50-33-010Z-2b90493c.jpg', 'clipboard-2026-11-07T08-50-33-012Z-1d8ec79f.jpg']
out_dir = Path(__file__).resolve().parent
cell_size = 297
for name, output in zip(files, ['planet_a.png', 'planet_b.png']):
    image = Image.open(source_dir / name).convert('RGB')
    sheet = Image.new('RGBA', (cell_size * 6, cell_size * 6))
    for row in range(6):
        for col in range(6):
            x0, x1 = round(col * image.width / 6), round((col + 1) * image.width / 6)
            y0, y1 = round(row * image.height / 6), round((row + 1) * image.height / 6)
            rgb = np.asarray(image.crop((x0, y0, x1, y1))).copy()
            h, w = rgb.shape[:2]
            pale = rgb.min(axis=2) >= 218
            connected = np.zeros((h, w), dtype=bool)
            queue = deque()
            for x in range(w):
                for y in (0, h - 1):
                    if pale[y, x] and not connected[y, x]:
                        connected[y, x] = True
                        queue.append((y, x))
            for y in range(h):
                for x in (0, w - 1):
                    if pale[y, x] and not connected[y, x]:
                        connected[y, x] = True
                        queue.append((y, x))
            while queue:
                y, x = queue.popleft()
                for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < h and 0 <= nx < w and pale[ny, nx] and not connected[ny, nx]:
                        connected[ny, nx] = True
                        queue.append((ny, nx))
            yy, xx = np.ogrid[:h, :w]
            outside_body = (xx - w / 2) ** 2 + (yy - h / 2) ** 2 > 116 ** 2
            connected |= pale & outside_body
            darkness = 255 - rgb.min(axis=2).astype(np.float32)
            alpha = np.full((h, w), 255, dtype=np.uint8)
            alpha[connected] = np.clip((darkness[connected] - 3) * 255 / 34, 0, 255).astype(np.uint8)
            # 将抗锯齿边缘从白底反混合，避免深色背景下出现白边。
            edge = connected & (alpha > 0) & (alpha < 255)
            a = alpha[edge].astype(np.float32)[:, None] / 255.0
            rgb[edge] = np.clip((rgb[edge].astype(np.float32) - 255 * (1 - a)) / a, 0, 255).astype(np.uint8)
            rgba = np.dstack((rgb, alpha))
            rgba[alpha == 0, :3] = 0
            frame = Image.fromarray(rgba, 'RGBA')
            sheet.paste(frame, (col * cell_size + (cell_size - w) // 2, row * cell_size + (cell_size - h) // 2))
    sheet.save(out_dir / output)
