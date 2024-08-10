import sys
import os.path
import argparse
import re
import datetime

#import torch
#import torchvision.transforms as transforms
from PIL import Image

import cv2
import numpy as np
import math

def fix_image_rotation_canny_hough(image_path, args):
    gaussian1 = hasattr(args, 'canny_gaussian1') and args.canny_gaussian1 or 71
    gaussian2 = hasattr(args, 'canny_gaussian2') and args.canny_gaussian2 or 71
    threshold1 = hasattr(args, 'canny_threshold1') and args.canny_threshold1 or 10
    threshold2 = hasattr(args, 'canny_threshold2') and args.canny_threshold2 or 1
    padding = hasattr(args, 'canny_padding') and args.canny_padding or 50

    hough_threshold = hasattr(args, 'hough_threshold') and args.hough_threshold or 400

    print (str(datetime.datetime.now()) + " " + fr"fixing rotation (canny + hough) on {image_path}")
    print (str(datetime.datetime.now()) + " " + fr"    gaussian blur {gaussian1}/{gaussian2}")
    print (str(datetime.datetime.now()) + " " + fr"    canny threshold1/threshold2/padding {threshold1}/{threshold2}/{padding}")

    # Read the image
    img = cv2.imread(image_path)

    if args.canny_debug:
        print(fr"     DEBUG: image dimensions: " + str(img.shape))

    # Convert to grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    if args.canny_debug:
        out_fn = re.sub(r"\.jpg", "_canny_01_grayscale.jpg", input_filename)
        cv2.imwrite(out_fn, gray)
        print(fr"     DEBUG: saved grayscale to: " + out_fn)

    # Apply Gaussian blur to reduce noise
    blurred = cv2.GaussianBlur(gray, (gaussian1, gaussian2), 0)

    if args.canny_debug:
        out_fn = re.sub(r"\.jpg", "_canny_02_blurred.jpg", input_filename)
        cv2.imwrite(out_fn, blurred)
        print(fr"     DEBUG: saved blurred to: " + out_fn)

    # Perform Canny edge detection
    edges = cv2.Canny(blurred, threshold1, threshold2)

    if args.canny_debug:
        out_fn = re.sub(r"\.jpg", "_canny_03_edges.jpg", input_filename)
        cv2.imwrite(out_fn, edges)
        print(fr"     DEBUG: saved edges to: " + out_fn)

    # Find the lines in the image using the Hough transform
    #
    # Output vector of lines.
    # Each line is represented by a 2 or 3 element vector (ρ,θ) or (ρ,θ,votes),
    # where ρ is the distance from the coordinate origin (0,0) (top-left corner of the image),
    # θ is the line rotation angle in radians ( 0∼vertical line,π/2∼horizontal line ),
    # and votes is the value of accumulator.
    #
    lines = cv2.HoughLines(edges, 0.9, np.pi / 180, hough_threshold)

    if args.hough_debug:
        print(fr"     DEBUG: detected lines: " + str(lines is not None and len(lines) or 0))
    
    avg_deviation = 0

    if lines is not None:

        img_lines = cv2.cvtColor(edges, cv2.COLOR_GRAY2BGR)

        min_rho = lines[0][0][0]
        min_rho_i = 0
        max_rho = lines[0][0][0]
        max_rho_i = 0
        for i in range(0, len(lines)):
            if lines[i][0][0] < min_rho:
                min_rho = lines[i][0][0]
                min_rho_i = i
            if lines[i][0][0] > max_rho:
                max_rho = lines[i][0][0]
                max_rho_i = i

        j = 0
        for i in range(0, len(lines)):
            j = j + 1
            rho = lines[i][0][0]
            theta = lines[i][0][1]

            line_deviation = 0
            if theta <= (math.pi / 4): # <45°
                line_deviation = theta - 0
                if args.hough_debug:
                    print(fr"     DEBUG: line {i} is closer to vertical")
            elif theta <= (math.pi / 2): # between 45° and 90°
                line_deviation = math.pi / 2 - theta
                if args.hough_debug:
                    print(fr"     DEBUG: line {i} is closer to horizontal")
            elif theta <= (3 * math.pi / 4): # between 90° and 135°
                line_deviation = theta - math.pi / 2
                if args.hough_debug:
                    print(fr"     DEBUG: line {i} is closer to horizontal")
            else: # between 135° and 180°
                line_deviation = math.pi - theta
                if args.hough_debug:
                    print(fr"     DEBUG: line {i} is closer to vertical")

            if line_deviation == 0:
                if args.hough_debug:
                    print(fr"     DEBUG: line {i} is vertical, excluding from avg_deviation calculation")
            elif line_deviation == math.pi / 2:
                if args.hough_debug:
                    print(fr"     DEBUG: line {i} is horizontal, excluding from avg_deviation calculation")
            else:
                avg_deviation = (avg_deviation + line_deviation) / j

            if args.hough_debug:
                print(fr"     DEBUG: line {i}: distance from (0,0) - {rho}, angle (rad) - {theta}")
                print(fr"     DEBUG: line {i} angle deviation from vert/horiz - {line_deviation}, avg_deviation - {avg_deviation}")

            a = math.cos(theta)
            b = math.sin(theta)
            x0 = a * rho
            y0 = b * rho
            pt1 = (int(x0 + 3*hough_threshold*(-b)), int(y0 + 3*hough_threshold*(a)))
            pt2 = (int(x0 - 3*hough_threshold*(-b)), int(y0 - 3*hough_threshold*(a)))
            cv2.line(img_lines, pt1, pt2, (0,0,255), 10)

        if args.hough_debug:
            out_fn = re.sub(r"\.jpg", "_canny_04_lines.jpg", input_filename)
            cv2.imwrite(out_fn, img_lines)
            print(fr"     DEBUG: saved lines to: " + out_fn)
    else:
        return img

    # Rotate the image by the average angle
    rows, cols = img.shape[:2]
    rotation_matrix = cv2.getRotationMatrix2D((cols / 2, rows / 2), np.rad2deg(avg_deviation), 1)
    rotated_image = cv2.warpAffine(
        src = img,
        M = rotation_matrix,
        dsize = (cols, rows),
        borderMode = cv2.BORDER_WRAP)

    if args.hough_debug:
        out_fn = re.sub(r"\.jpg", "_canny_05_rotated.jpg", input_filename)
        cv2.imwrite(out_fn, rotated_image)
        print(fr"     DEBUG: saved rotated to: " + out_fn)

    return rotated_image


def remove_empty_space_edge_detection_canny(image_path, img_data, args, dbg_imgn = 0):
    threshold1 = hasattr(args, 'canny_threshold1') and args.canny_threshold1 or 380
    threshold2 = hasattr(args, 'canny_threshold2') and args.canny_threshold2 or 380
    padding = hasattr(args, 'canny_padding') and args.canny_padding or 30

    if img_data is not None:
        print (fr"removing empty space (canny) from {image_path} (binary image data), threshold1/threshold2/padding {threshold1}/{threshold2}/{padding}")

        # Reuse previously generated image data
        img = img_data
    else:
        print (fr"removing empty space (canny) from {image_path}, threshold1/threshold2/padding {threshold1}/{threshold2}/{padding}")

        # Read the image from the file
        img = cv2.imread(image_path)


    if args.canny_debug:
        print(fr"     DEBUG: image dimensions: " + str(img.shape))
    
    # Convert to grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    if args.canny_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_canny_{dbg_imgn:02d}_grayscale.jpg", input_filename)
        cv2.imwrite(out_fn, gray)
        print(fr"     DEBUG: saved grayscale to: " + out_fn)
    
    # Apply Gaussian blur to reduce noise
    blurred = cv2.GaussianBlur(gray,
        (
            hasattr(args, 'canny_gaussian1') and args.canny_gaussian1 or 5,
            hasattr(args, 'canny_gaussian2') and args.canny_gaussian2 or 5
        ), 0)
    
    if args.canny_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_canny_{dbg_imgn:02d}_blurred.jpg", input_filename)
        cv2.imwrite(out_fn, blurred)
        print(fr"     DEBUG: saved blurred to: " + out_fn)
    
    # Perform Canny edge detection
    edges = cv2.Canny(blurred, threshold1, threshold2)

    if args.canny_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_canny_{dbg_imgn:02d}_edges.jpg", input_filename)
        cv2.imwrite(out_fn, edges)
        print(fr"     DEBUG: saved edges to: " + out_fn)
    
    # Find contours from the edges
    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    print(fr"found " + str(len(contours)) + " contours")
    
    if len(contours) == 0:
        return img

    # Find the bounding rectangle of all contours
    x_min, y_min, x_max, y_max = float('inf'), float('inf'), 0, 0
    for contour in contours:
        x, y, w, h = cv2.boundingRect(contour)
        x_min = min(x_min, x)
        y_min = min(y_min, y)
        x_max = max(x_max, x + w)
        y_max = max(y_max, y + h)
    
    # Add padding
    x_min = max(0, x_min - padding)
    y_min = max(0, y_min - padding)
    x_max = min(img.shape[1], x_max + padding)
    y_max = min(img.shape[0], y_max + padding)
    
    # Crop the image
    cropped = img[y_min:y_max, x_min:x_max]
    
    return cropped

def remove_non_uniform_empty_space_otsu(image_path, threshold=0):
    # Read the image
    img = cv2.imread(image_path)
    
    # Convert to grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    
    # Apply Gaussian blur to reduce noise
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    
    # Use Otsu's method for thresholding
    _, thresh = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    
    # Find contours
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    
    # Find the largest contour (assumed to be the main content)
    main_contour = max(contours, key=cv2.contourArea)
    
    # Get bounding rectangle
    x, y, w, h = cv2.boundingRect(main_contour)
    
    # Add some padding
    padding = threshold
    x = max(0, x - padding)
    y = max(0, y - padding)
    w = min(img.shape[1] - x, w + 2*padding)
    h = min(img.shape[0] - y, h + 2*padding)

    print(fr"Largest contour: x {x}, y {y}, w {w}, h {h}")
    
    # Crop the image
    cropped = img[y:y+h, x:x+w]
    
    return cropped

def remove_empty_space_torch(image_path, args):
    threshold = hasattr(args, 'torch_threshold') and args.torch_threshold or 30
    padding = hasattr(args, 'torch_padding') and args.torch_padding or 10

    print (fr"running torch on {image_path}, threshold/padding {threshold}/{padding}")

    # Load the image
    image = Image.open(image_path)
    
    # Convert to PyTorch tensor
    to_tensor = transforms.ToTensor()
    img_tensor = to_tensor(image).unsqueeze(0)  # Add batch dimension

    # Convert to grayscale
    grayscale = torch.mean(img_tensor, dim=1, keepdim=True)

    # Compute gradients (simple edge detection)
    sobel_x = torch.tensor([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]).float().view(1, 1, 3, 3)
    sobel_y = torch.tensor([[-1, -2, -1], [0, 0, 0], [1, 2, 1]]).float().view(1, 1, 3, 3)

    edges_x = torch.abs(torch.nn.functional.conv2d(grayscale, sobel_x, padding=1))
    edges_y = torch.abs(torch.nn.functional.conv2d(grayscale, sobel_y, padding=1))
    edges = torch.sqrt(edges_x**2 + edges_y**2)

    # Threshold the edges
    edges_binary = (edges > threshold).float()

    # Find non-zero indices
    non_zero = torch.nonzero(edges_binary.squeeze())

    print (fr"non zero indices found: " + str(len(non_zero)))
    
    if len(non_zero) == 0:
        return image  # Return original if no edges found

    # Compute bounding box
    y_min, x_min = torch.min(non_zero, dim=0).values
    y_max, x_max = torch.max(non_zero, dim=0).values

    # Add padding
    x_min = max(0, x_min - padding)
    y_min = max(0, y_min - padding)
    x_max = min(img_tensor.shape[3] - 1, x_max + padding)
    y_max = min(img_tensor.shape[2] - 1, y_max + padding)

    # Crop the image tensor
    cropped_tensor = img_tensor[:, :, y_min:y_max+1, x_min:x_max+1]

    # Convert back to PIL Image
    to_pil = transforms.ToPILImage()
    cropped_image = to_pil(cropped_tensor.squeeze(0))

    return cropped_image

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--filename', type=str)
    parser.add_argument('--run', type=str)
    parser.add_argument('--canny-threshold1', type=int)
    parser.add_argument('--canny-threshold2', type=int)
    parser.add_argument('--canny-gaussian1', type=int)
    parser.add_argument('--canny-gaussian2', type=int)
    parser.add_argument('--canny-padding', type=int)
    parser.add_argument('--canny-debug', type=bool)
    parser.add_argument('--torch-threshold', type=int)
    parser.add_argument('--torch-padding', type=int)
    parser.add_argument('--hough-debug', type=bool)
    parser.add_argument('--hough-threshold', type=int)

    args = parser.parse_args()

    input_filename = hasattr(args, 'filename') and args.filename or ""
    if (not os.path.isfile(input_filename)):
        print("\n" fr"Need an image file to proceed, got: [{input_filename}]" "\n")
        parser.print_help()
        sys.exit(2)

    print (str(datetime.datetime.now()) + " " + fr"working on {input_filename}")

    # --run canny --canny-threshold1 10 --canny-threshold2 1 --canny-gaussian1 71 --canny-gaussian2 71 --canny-padding 50 --filename 'Z:\of-15111-2247\OF 15111_2247_001.jpg'
    if hasattr(args, 'run') and args.run == r"canny":
        cropped_image = remove_empty_space_edge_detection_canny(image_path = input_filename, img_data = None, args = args)
        output_filename = re.sub(r"\.jpg", "_canny_cropped.jpg", input_filename)
        cv2.imwrite(output_filename, cropped_image)
        print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")

    if hasattr(args, 'run') and args.run == r"torch":
        cropped_image = remove_empty_space_torch(input_filename, args)
        output_filename = re.sub(r"\.jpg", "_torch.jpg", input_filename)
        cropped_image.save(output_filename)
        print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")

    # --run fix-rotation --canny-threshold1 10 --canny-threshold2 1 --canny-gaussian1 71 --canny-gaussian2 71 --canny-padding 50  --filename 'Z:\of-15111-2247\OF 15111_2247_001.jpg'
    if hasattr(args, 'run') and args.run == r"fix-rotation":
        rotated_image = fix_image_rotation_canny_hough(input_filename, args)
        cropped_image = remove_empty_space_edge_detection_canny(
            image_path = input_filename,
            img_data = rotated_image,
            args = args,
            dbg_imgn = 5)
        output_filename = re.sub(r"\.jpg", "_fixed_rotation.jpg", input_filename)
        cv2.imwrite(output_filename, cropped_image)
        print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")
