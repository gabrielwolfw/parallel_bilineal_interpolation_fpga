#!/usr/bin/env python3

from PIL import Image, ImageDraw, ImageFont
import numpy as np
import os

def save_pgm(img, filename):
    """Save numpy array as PGM (Portable GrayMap) format"""
    height, width = img.shape
    with open(filename, 'wb') as f:
        # PGM header (P5 = binary format)
        f.write(f"P5\n{width} {height}\n255\n".encode('ascii'))
        # Binary pixel data
        f.write(img.tobytes())

def create_gradient_image(width, height, filename):
    img = np.zeros((height, width), dtype=np.uint8)
    
    for y in range(height):
        for x in range(width):
            value = int((x / width) * 255)
            img[y, x] = value
    
    save_pgm(img, filename)
    print(f"Created: {filename} ({width}x{height})")

def create_checkerboard_image(width, height, square_size, filename):
    img = np.zeros((height, width), dtype=np.uint8)
    
    for y in range(height):
        for x in range(width):
            if ((x // square_size) + (y // square_size)) % 2 == 0:
                img[y, x] = 255
            else:
                img[y, x] = 0
    
    save_pgm(img, filename)
    print(f"Created: {filename} ({width}x{height})")

def create_circle_image(width, height, filename):
    img = np.zeros((height, width), dtype=np.uint8)
    
    center_x = width // 2
    center_y = height // 2
    max_radius = min(center_x, center_y)
    
    for y in range(height):
        for x in range(width):
            dx = x - center_x
            dy = y - center_y
            distance = np.sqrt(dx*dx + dy*dy)
            
            if distance <= max_radius:
                value = int(255 * (1 - distance / max_radius))
                img[y, x] = value
    
    save_pgm(img, filename)
    print(f"Created: {filename} ({width}x{height})")

def create_text_image(width, height, text, filename):
    img = Image.new('L', (width, height), color=128)
    draw = ImageDraw.Draw(img)
    
    # Try multiple font paths for cross-platform compatibility
    font = None
    font_paths = [
        # Windows fonts
        "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        # Linux fonts
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        # macOS fonts
        "/System/Library/Fonts/Helvetica.ttc"
    ]
    
    for font_path in font_paths:
        try:
            if os.path.exists(font_path):
                font = ImageFont.truetype(font_path, 80)
                break
        except:
            continue
    
    # Fallback to default font
    if font is None:
        font = ImageFont.load_default()
        print(f"Warning: Using default font for {filename} (TrueType fonts not found)")
    
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    x = (width - text_width) // 2
    y = (height - text_height) // 2
    
    draw.rectangle([(0, 0), (width, height)], fill=200)
    draw.text((x, y), text, fill=0, font=font)
    
    # Convert PIL Image to numpy array and save as PGM
    img_array = np.array(img, dtype=np.uint8)
    save_pgm(img_array, filename)
    print(f"Created: {filename} ({width}x{height})")

def main():
    os.makedirs('images', exist_ok=True)
    
    create_gradient_image(256, 256, 'images/01.pgm')
    
    create_checkerboard_image(320, 320, 32, 'images/02.pgm')
    
    create_circle_image(400, 400, 'images/03.pgm')
    
    create_text_image(512, 512, 'FPGA', 'images/04.pgm')
    
    print("\nTest images generated successfully!")
    print("Format: PGM (Portable GrayMap) - 8 bits per pixel")
    print("Note: PGM files can be viewed with GIMP, ImageMagick, or any image viewer")

if __name__ == '__main__':
    main()
