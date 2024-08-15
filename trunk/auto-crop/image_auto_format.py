import sys
import os.path
from pathlib import Path
import argparse
import re
import datetime
import shutil

#import torch
#import torchvision.transforms as transforms
from PIL import Image

import cv2
import numpy as np
import math

def write_jpeg(filename, filedata):
    cv2.imwrite(filename, filedata, [cv2.IMWRITE_JPEG_QUALITY, 80])

def calc_line_deviation(theta, args):
    line_deviation = 0
    if theta <= (math.pi / 4): # <45°
        line_deviation = theta - 0
        if args.hough_debug:
            print(fr"     DEBUG: angle {theta} (" + str(math.degrees(theta)) + "°) is closer to vertical")
    elif theta <= (math.pi / 2): # between 45° and 90°
        line_deviation = theta - math.pi / 2
        if args.hough_debug:
            print(fr"     DEBUG: angle {theta} (" + str(math.degrees(theta)) + "°) is closer to horizontal")
    elif theta <= (3 * math.pi / 4): # between 90° and 135°
        line_deviation = theta - math.pi / 2
        if args.hough_debug:
            print(fr"     DEBUG: angle {theta} (" + str(math.degrees(theta)) + "°) is closer to horizontal")
    else: # between 135° and 180°
        line_deviation = theta - math.pi
        if args.hough_debug:
            print(fr"     DEBUG: angle {theta} (" + str(math.degrees(theta))
                   + "°) is closer to vertical")

    return line_deviation

def fix_image_rotation_canny_hough(
        image_path,
        destination_dir,
        args):
    gaussian1 = hasattr(args, 'canny_gaussian1') and args.canny_gaussian1 or 71
    gaussian2 = hasattr(args, 'canny_gaussian2') and args.canny_gaussian2 or 71
    threshold1 = hasattr(args, 'canny_threshold1') and args.canny_threshold1 or 10
    threshold2 = hasattr(args, 'canny_threshold2') and args.canny_threshold2 or 1
    padding = hasattr(args, 'canny_padding') and args.canny_padding or 50

    hough_threshold = hasattr(args, 'hough_threshold') and args.hough_threshold or 400
    hough_theta_resolution_degrees = float(hasattr(args, 'hough_theta_resolution_degrees') and args.hough_theta_resolution_degrees or 1)
    hough_theta_resolution_rad = math.radians(hough_theta_resolution_degrees)
    hough_rho_resolution_pixels = float(hasattr(args, 'hough_rho_resolution_pixels') and args.hough_rho_resolution_pixels or 1)

    if destination_dir is not None:
        dbg_destination = destination_dir
    else:
        dbg_destination = os.path.dirname(image_path)

    print (str(datetime.datetime.now()) + " " + fr"fixing rotation (canny + hough) on {image_path}")
    print (str(datetime.datetime.now()) + " " + fr"    gaussian blur {gaussian1}/{gaussian2}")
    print (str(datetime.datetime.now()) + " " + fr"    canny threshold1/threshold2/padding {threshold1}/{threshold2}/{padding}")
    print (str(datetime.datetime.now()) + " " + fr"    hough theta_resolution deg/rad {hough_theta_resolution_degrees}/{hough_theta_resolution_rad}")
    print (str(datetime.datetime.now()) + " " + fr"    hough rho_resolution pixels {hough_rho_resolution_pixels}")

    # Read the image
    img = cv2.imread(image_path)

    if args.canny_debug:
        print(fr"     DEBUG: image dimensions: " + str(img.shape))

    # Convert to grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    if args.canny_debug:
        out_fn = re.sub(r"\.jpg", "_canny_01_grayscale.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, gray)
        print(fr"     DEBUG: saved grayscale to: " + out_fn)

    # Apply Gaussian blur to reduce noise
    blurred = cv2.GaussianBlur(gray, (gaussian1, gaussian2), 0)

    if args.canny_debug:
        out_fn = re.sub(r"\.jpg", "_canny_02_blurred.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, blurred)
        print(fr"     DEBUG: saved blurred to: " + out_fn)

    # Perform Canny edge detection
    edges = cv2.Canny(blurred, threshold1, threshold2)

    if args.canny_debug:
        out_fn = re.sub(r"\.jpg", "_canny_03_edges.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, edges)
        print(fr"     DEBUG: saved edges to: " + out_fn)

    # https://docs.opencv.org/3.4/d9/db0/tutorial_hough_lines.html
    # https://stackoverflow.com/questions/4709725/explain-hough-transformation
    #
    # Find the lines in the image using the Hough transform
    #
    # Output vector of lines.
    # Each line is represented by a 2 or 3 element vector (ρ,θ) or (ρ,θ,votes),
    # where ρ is the distance from the coordinate origin (0,0) (top-left corner of the image),
    # θ is the line rotation angle in radians ( 0∼vertical line,π/2∼horizontal line ),
    # and votes is the value of accumulator.
    #
    lines = cv2.HoughLines(edges, hough_rho_resolution_pixels, hough_theta_resolution_rad, hough_threshold)

    if args.hough_debug:
        print(fr"     DEBUG hough: detected lines: " + str(lines is not None and len(lines) or 0))
    
    avg_deviation = 0

    if lines is not None:

        img_lines = cv2.cvtColor(edges, cv2.COLOR_GRAY2BGR)

        min_rho = lines[0][0][0]
        min_rho_i = -1
        max_rho = lines[0][0][0]
        max_rho_i = -1
        for i in range(0, len(lines)):
            if args.hough_debug:
                print(fr"     DEBUG hough select min/max: line {i} angle: " + str(math.degrees(lines[i][0][1])) + "°")

            if (math.degrees(calc_line_deviation(lines[i][0][1], args)) < 10 and
                math.degrees(calc_line_deviation(lines[i][0][1], args)) > -10):
                if lines[i][0][0] < min_rho:
                    min_rho = lines[i][0][0]
                    min_rho_i = i
                if lines[i][0][0] > max_rho:
                    max_rho = lines[i][0][0]
                    max_rho_i = i

        j = 0
        for i in range(0, len(lines)):
            rho = lines[i][0][0]
            theta = lines[i][0][1]

            line_deviation = calc_line_deviation(theta, args)

            if line_deviation == 0:
                if args.hough_debug:
                    print(fr"     DEBUG hough avg deviation: line {i} is vertical, excluding from avg_deviation calculation")
            elif line_deviation == math.pi / 2:
                if args.hough_debug:
                    print(fr"     DEBUG hough avg deviation: line {i} is horizontal, excluding from avg_deviation calculation")
            elif math.degrees(line_deviation) > 10 or math.degrees(line_deviation) < -10:
                if args.hough_debug:
                    print(fr"     DEBUG hough avg deviation: line {i} is too inclined, excluding from avg_deviation calculation")
            else:
                if args.hough_debug:
                    print(fr"     DEBUG hough avg deviation: line {i}: avg_deviation before, line_deviation - {avg_deviation}, {line_deviation}")

                j = j + 1
                avg_deviation = (avg_deviation + line_deviation) / 2
                if args.hough_debug:
                    print(fr"     DEBUG hough avg deviation: line {i}: avg_deviation after, j - {avg_deviation}, {j}")

            if args.hough_debug:
                print(fr"     DEBUG hough avg deviation: line {i}: rho - {rho}, theta (deg) - " + str(math.degrees(theta)))
                print(fr"     DEBUG hough avg deviation: line {i} angle deviation - " + str(math.degrees(line_deviation)) + ", avg_deviation - " + str(math.degrees(avg_deviation)))

            a = math.cos(theta)
            b = math.sin(theta)
            x0 = a * rho
            y0 = b * rho
            pt1 = (int(x0 + 3*hough_threshold*(-b)), int(y0 + 3*hough_threshold*(a)))
            pt2 = (int(x0 - 3*hough_threshold*(-b)), int(y0 - 3*hough_threshold*(a)))
            cv2.line(img_lines, pt1, pt2, (0,0,255), 1)

        if args.hough_debug:
            out_fn = re.sub(r"\.jpg", "_canny_05_lines.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
            write_jpeg(out_fn, img_lines)
            print(fr"     DEBUG: saved lines to: " + out_fn)
    else:
        return img

    if args.hough_debug:
        print(fr"     DEBUG hough rotating by avg_deviation " + str(math.degrees(avg_deviation)) + " " + str(np.rad2deg(avg_deviation)))
    # Rotate the image by the average angle
    rows, cols = img.shape[:2]
    rotation_matrix = cv2.getRotationMatrix2D((cols / 2, rows / 2), np.rad2deg(avg_deviation), 1)
    rotated_image = cv2.warpAffine(
        src = img,
        M = rotation_matrix,
        dsize = (cols, rows),
        borderMode = cv2.BORDER_WRAP)

    if args.hough_debug:
        out_fn = re.sub(r"\.jpg", "_canny_04_rotated.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, rotated_image)
        print(fr"     DEBUG: saved rotated to: " + out_fn)

    return rotated_image


def remove_empty_space_edge_detection_canny(
        image_path,
        img_data,
        destination_dir,
        args,
        dbg_imgn = 0
        ):
    
    threshold1 = hasattr(args, 'canny_threshold1') and args.canny_threshold1 or 380
    threshold2 = hasattr(args, 'canny_threshold2') and args.canny_threshold2 or 380
    padding = hasattr(args, 'canny_padding') and args.canny_padding or 30

    if destination_dir is not None:
        dbg_destination = destination_dir
    else:
        dbg_destination = os.path.dirname(image_path)

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
        out_fn = re.sub(r"\.jpg", fr"_canny_{dbg_imgn:02d}_grayscale.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, gray)
        print(fr"     DEBUG: saved grayscale to: " + out_fn)
    
    # Apply Gaussian blur to reduce noise
    blurred = cv2.GaussianBlur(gray,
        (
            hasattr(args, 'canny_gaussian1') and args.canny_gaussian1 or 5,
            hasattr(args, 'canny_gaussian2') and args.canny_gaussian2 or 5
        ), 0)
    
    if args.canny_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_canny_{dbg_imgn:02d}_blurred.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, blurred)
        print(fr"     DEBUG: saved blurred to: " + out_fn)
    
    # Perform Canny edge detection
    edges = cv2.Canny(blurred, threshold1, threshold2)

    if args.canny_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_canny_{dbg_imgn:02d}_edges.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, edges)
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

def check_and_create_destination(destination_dir):
    if (not os.path.isdir(destination_dir)):
        directory = Path(destination_dir)
        try:
            directory.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            print(fr"An error occurred while creating directory {destination_dir}: {e}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--filename', type=str)
    parser.add_argument('--source-dir', type=str)
    parser.add_argument('--destination-dir', type=str)
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
    parser.add_argument('--hough-theta-resolution-degrees', type=float)
    parser.add_argument('--hough-rho-resolution-pixels', type=float)
    parser.add_argument('--hough-threshold', type=int)
    parser.add_argument('--copy-source-to-destination', type=bool)
   
    args = parser.parse_args()

    source_dir = args.source_dir if hasattr(args, 'source_dir') else None
    destination_dir = args.destination_dir if hasattr(args, 'destination_dir') else None
    input_filename = args.filename if hasattr(args, 'filename') else None
    run = hasattr(args, 'run') and args.run or None

    if (run != "trim-canny" and run != "trim-torch" and run != "fix-rotation"):
        parser.print_help()
        print("\n" fr"Need --run with one of: trim-canny, trim-torch, fix-rotation" "\n")
        sys.exit(2)

    if (source_dir is not None and input_filename is not None):
        parser.print_help()
        print("\n" fr"Choose either --filename (to process one file) or --source-dir (to process a directory), not both!" "\n")
        sys.exit(2)
    elif (source_dir is not None):
        if (destination_dir is None):
            parser.print_help()
            print("\n" fr"Specifying --source-dir implies specifying --destination-dir!" "\n")
            sys.exit(2)

        check_and_create_destination(destination_dir)

        if (os.path.isdir(source_dir)):
            print (str(datetime.datetime.now()) + " " + fr"working on {source_dir}")
            for afn in os.listdir(source_dir):
                print (str(datetime.datetime.now()) + "     working on " + os.path.join(source_dir, afn))

                if hasattr(args, 'copy_source_to_destination') and args.copy_source_to_destination:
                    shutil.copy2(os.path.join(source_dir, afn), destination_dir)

                if hasattr(args, 'run') and args.run == r"trim-canny":
                    cropped_image = remove_empty_space_edge_detection_canny(
                        image_path = os.path.join(source_dir, afn),
                        img_data = None,
                        args = args,
                        destination_dir = destination_dir)
                    output_filename = re.sub(r"\.jpg", "_canny_cropped.jpg", os.path.join(destination_dir, afn))
                    write_jpeg(output_filename, cropped_image)
                    print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")

                if hasattr(args, 'run') and args.run == r"fix-rotation":
                    rotated_image = fix_image_rotation_canny_hough(
                        image_path = os.path.join(source_dir, afn),
                        args = args,
                        destination_dir = destination_dir)
                    cropped_image = remove_empty_space_edge_detection_canny(
                        image_path = input_filename,
                        img_data = rotated_image,
                        args = args,
                        dbg_imgn = 5,
                        destination_dir = destination_dir)
                    output_filename = re.sub(r"\.jpg", "_fixed_rotation.jpg", os.path.join(destination_dir, afn))
                    write_jpeg(output_filename, cropped_image)
                    print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")


        else:
            parser.print_help()
            print("\n" fr"Non-existent directory specified: [{source_dir}]" "\n")
            sys.exit(2)
    elif (input_filename is not None):
        if(os.path.isfile(input_filename)):
            print (str(datetime.datetime.now()) + " " + fr"working on {input_filename}")

            if destination_dir is not None:
                check_and_create_destination(destination_dir)
                tmp_destination = destination_dir
            else:
                tmp_destination = os.path.dirname(input_filename)

            if hasattr(args, 'copy_source_to_destination') and args.copy_source_to_destination:
                shutil.copy2(input_filename, tmp_destination)

            # --run canny --canny-threshold1 10 --canny-threshold2 1 --canny-gaussian1 71 --canny-gaussian2 71 --canny-padding 50 --filename 'Z:\of-15111-2247\OF 15111_2247_001.jpg'
            if hasattr(args, 'run') and args.run == r"trim-canny":
                cropped_image = remove_empty_space_edge_detection_canny(
                    image_path = input_filename,
                    img_data = None,
                    args = args,
                    destination_dir = tmp_destination)
                output_filename = re.sub(r"\.jpg", "_canny_cropped.jpg", os.path.join(tmp_destination, os.path.basename(input_filename)))
                write_jpeg(output_filename, cropped_image)
                print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")

            if hasattr(args, 'run') and args.run == r"trim-torch":
                cropped_image = remove_empty_space_torch(input_filename, args)
                output_filename = re.sub(r"\.jpg", "_torch.jpg", input_filename)
                cropped_image.save(output_filename)
                print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")

            # --run fix-rotation --canny-threshold1 10 --canny-threshold2 1 --canny-gaussian1 71 --canny-gaussian2 71 --canny-padding 50  --filename 'Z:\of-15111-2247\OF 15111_2247_001.jpg'
            if hasattr(args, 'run') and args.run == r"fix-rotation":
                rotated_image = fix_image_rotation_canny_hough(
                    image_path = input_filename,
                    args = args,
                    destination_dir = tmp_destination)
                cropped_image = remove_empty_space_edge_detection_canny(
                    image_path = input_filename,
                    img_data = rotated_image,
                    args = args,
                    dbg_imgn = 5,
                    destination_dir = tmp_destination)
                output_filename = re.sub(r"\.jpg", "_fixed_rotation_cropped.jpg", os.path.join(tmp_destination, os.path.basename(input_filename)))
                write_jpeg(output_filename, cropped_image)
                print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")

        else:
            parser.print_help()
            print("\n" fr"Need an image file to proceed, got: [{input_filename}]" "\n")
            sys.exit(2)
    else:
        parser.print_help()
        print("\n" fr"Need either --filename (to process one file) or --source-dir (to process a directory), got none!" "\n")
        sys.exit(2)

if __name__ == "__main__":
    main()
