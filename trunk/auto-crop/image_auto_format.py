import sys
import os.path
from pathlib import Path
import argparse
import re
import datetime
import shutil
import random

from collections import defaultdict

from PIL import Image

import cv2
import numpy as np
import math

from scipy.spatial import distance_matrix

import exifread

class ScannedPage:
    def debug_print(self, astr):
        if self.args.debug:
            print (str(datetime.datetime.now()) + " " + astr)

    def __init__(self,
                 filename,
                 args = defaultdict(lambda:None),
                 variant = 0
                 ):
        if not os.path.isfile(filename):
            raise ValueError(r"Need an image file to proceed, got: [{}] (check if it exists)".format(filename))

        # filename with original scan
        self.filename = filename

        # image representations (including original)
        self.images = defaultdict(lambda:None)

        # image transformations
        self.transforms = defaultdict(lambda:None)

        # written images
        self.written_images = defaultdict(lambda:None)

        self.args = args

        if hasattr(args, 'destination_dir'):
            if (not os.path.isdir(args.destination_dir)):
                directory = Path(args.destination_dir)
                try:
                    directory.mkdir(parents=True, exist_ok=True)
                except Exception as e:
                    raise ValueError(r"An error occurred while creating directory {}: ".format(args.destination_dir) + str(e))
            self.destination_path = args.destination_dir
        else:
            self.destination_path = os.path.dirname(self.filename)

        if args.copy_source_to_destination and not os.path.samefile(os.path.dirname(self.filename), self.destination_path):
            shutil.copy2(self.filename, self.destination_path)
            self.debug_print(fr"copied original [{self.filename}] to [{self.destination_path}]")

        # multiple original scans with different transformations
        self.variant = variant

    def read(self):
        if self.images['original'] is None:
            self.debug_print(fr"reading {self.filename}")
            self.images['original'] = cv2.imread(self.filename)

    def write(self, image_type, image_suffix = None):
        if self.written_images[image_type] is not None:
            raise ValueError(r"Image type [{}] has already been written into ".format(image_type) + str(self.written_images[image_type]))

        if self.images[image_type] is None:
            raise ValueError("Requested to write non-existent image type '{}'".format(image_type))

        if image_suffix is None:
            image_suffix = "_" + str(image_type)

        output_filename = re.sub(r"\.jpg",
                                 fr"{image_suffix}.jpg",
                                 os.path.join(self.destination_path, os.path.basename(self.filename)))

        self.debug_print(fr"writing {image_type} to {output_filename}")
        write_jpeg(output_filename, self.images[image_type])
        self.written_images[image_type] = output_filename

    def prepare_edges(self):
        if self.images['original'] is None:
            self.read()

        # Original image converted to grayscale
        if self.images['original_gray'] is None:
            self.images['original_gray'] = cv2.cvtColor(self.images["original"], cv2.COLOR_BGR2GRAY)
            if self.args.debug:
                n = self.variant * 4 + 1
                self.write('original_gray', '__' + fr"{n:02d}" + '_gray')

        # Original image converted to grayscale and blurred
        if self.images['original_gray_blurred'] is None:
            # Apply Gaussian blur to reduce noise
            self.images['original_gray_blurred'] = cv2.GaussianBlur(
                self.images['original_gray'],
                (self.args.canny_gaussian1, self.args.canny_gaussian2),
                0)
            if self.args.debug:
                n = self.variant * 4 + 2
                self.write('original_gray_blurred', '__' + fr"{n:02d}" + '_gray_blurred')

        if self.images['original_gray_blurred_edges'] is None:
            # Perform Canny edge detection
            self.images['original_gray_blurred_edges'] = cv2.Canny(
                self.images['original_gray_blurred'],
                self.args.canny_threshold1,
                self.args.canny_threshold2)
            if self.args.debug:
                n = self.variant * 4 + 3
                self.write('original_gray_blurred_edges', '__' + fr"{n:02d}" + '_gray_blurred_edges')

    def prepare_edge_contours(self):
        if self.transforms['original_gray_blurred_edges_contours'] is None:
            contours, _ = cv2.findContours(self.images['original_gray_blurred_edges'], cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            self.transforms['original_gray_blurred_edges_contours'] = contours
            self.debug_print(fr"Got [" + str(len(self.transforms['original_gray_blurred_edges_contours'])) + "] contours from edges")

    def prepare_edge_contours_centroids(self):
        if self.transforms['original_gray_blurred_edges_contours_centroids'] is None:
            # Extract centroids of all contours
            centroids = []
            centroids_with_annotations = []
            for i in range(len(self.transforms['original_gray_blurred_edges_contours'])):
                M = cv2.moments(self.transforms['original_gray_blurred_edges_contours'][i])

                # M['m00'] can be zero in a few scenarios:
                #   1. Empty contour: If the contour has no points or is empty, all moments including M['m00'] will be zero.
                #   2. Very small contour: For extremely small contours (e.g., a single pixel), numerical precision issues might lead to M['m00'] being computed as zero.
                #   3. Non-contour input: If the input to cv2.moments() is not a valid contour (e.g., an all-zero array), it may result in zero moments.
                #   4. Binary image with all zeros: If the contour is extracted from a binary image that contains all zeros, M['m00'] will be zero.
                #
                # It's important to note that M['m00'] represents the 0th order moment, which is equivalent
                # to the area of the contour. In most practical cases with valid contours, M['m00'] should be positive.
                # When using moments for further calculations (like finding centroids), it's a good practice
                # to check if M['m00'] is zero to avoid division by zero errors.

                if M['m00'] != 0:
                    cx = int(M['m10'] / M['m00'])
                    cy = int(M['m01'] / M['m00'])

                    centroids.append((cx, cy))

                    # 0: {'centroid': (3266, 5983)}
                    # 1: {'centroid': (1578, 4523)}
                    # 6: {'centroid': (1590, 4522)}
                    # 7: {'centroid': (1593, 4515)}
                    # 8: {'centroid': (1561, 4515)}
                    centroids_with_annotations.append({
                        'centroid': (cx,cy),
                        'contour_n': i,
                        'centroid_n': len(centroids) - 1
                        })

            self.transforms['original_gray_blurred_edges_contours_centroids'] = centroids
            self.transforms['original_gray_blurred_edges_contours_centroids_annotations'] = centroids_with_annotations

            self.debug_print(fr"prepared [" + str(len(centroids)) + "] centroids from [" + 
                             str(len(self.transforms['original_gray_blurred_edges_contours'])) +
                             "] contours")

    def detect_artifacts(self):
        self.prepare_edges()
        self.prepare_edge_contours()

        # can't continue the transform
        if len(self.transforms['original_gray_blurred_edges_contours']) == 0:
            return {
                'error': "Can't find contours in the picture",
                'image': self.images['original']
            }

        self.prepare_edge_contours_centroids()

        if len(self.transforms['original_gray_blurred_edges_contours_centroids']) < 2:
            return {
                'error': "Can't find enough centroids to calculate artifact measure",
                'image': self.images['original']
            }

        if self.transforms['original_gray_blurred_edges_contours_centroids_artifact_measure'] is None:
            centroids = self.transforms['original_gray_blurred_edges_contours_centroids']
            centroids_with_annotations = self.transforms['original_gray_blurred_edges_contours_centroids_annotations']

            self.debug_print(fr"generating distance matrix")
            # time consuming if > 20,000 centroids
            dist_matrix = distance_matrix(centroids, centroids)

            # For each centroid, calculate the sum of distances to all other centroids
            for i in range(len(centroids)):
                distances = dist_matrix[i]
                centroids_with_annotations[i]['sum_distances'] = np.round(np.sum(distances))

            # sort by artifact measure
            centroids_distances_sorted = sorted(centroids_with_annotations, key=lambda x: x['sum_distances'])

            # select % of the closest centroids as non-artifacts
            _, j = math.modf(len(centroids_distances_sorted) * self.args.artifacts_majority_threshold)

            # there should be at least one centroid considered the subject of an image
            if j < 1:
                return {
                    'error': fr"{self.args.artifacts_majority_threshold} is too low, try increasing",
                    'image': self.images['original']
                }

            # Find the bounding rectangle of all centroids except artifacts
            x_min, y_min, x_max, y_max = float('inf'), float('inf'), 0, 0

            height, width = self.images['original_gray_blurred_edges'].shape

            # find the largest bounding rect without artifacts
            x1_left, y1_top, x2_right, y2_bottom = 0, 0, width, height

            prev_distance = None
            jump_centroid = None
            for i in range(len(centroids_distances_sorted)):
                # current centroid coordinates
                x, y, w, h = cv2.boundingRect(
                    self.transforms['original_gray_blurred_edges_contours'][centroids_distances_sorted[i]['contour_n']])

                if i < j:
                    # can't be an artifact - by definition. adjust bounding rect (increase) of the main subject -
                    # from the "center" - centroid with the smallest measure, there's at least one such centroid
                    x_min = min(x_min, x)
                    y_min = min(y_min, y)
                    x_max = max(x_max, x + w)
                    y_max = max(y_max, y + h)
                else:
                    if jump_centroid is None:
                        if (centroids_distances_sorted[i]['sum_distances'] - prev_distance) / prev_distance > \
                            self.args.artifacts_discontinuity_threshold:

                            jump_centroid = i
                        else:
                            # not an artifact - adjust bounding rect of the main subject
                            x_min = min(x_min, x)
                            y_min = min(y_min, y)
                            x_max = max(x_max, x + w)
                            y_max = max(y_max, y + h)

                    # detected artifact - adjust bounding rect (decrease) which does not contain artifacts
                    if jump_centroid:
                        if x + w < x_min:
                            x1_left = max(x + w, x1_left)
                        if x > x_max:
                            x2_right = min(x, x2_right)
                        if y + h < y_min:
                            y1_top = max(y + h, y1_top)
                        if y > y_max:
                            y2_bottom = min(y, y2_bottom)

                    self.debug_print(
                        fr"{i}: " + str(centroids_distances_sorted[i]['sum_distances']) + ("" if jump_centroid is None else " - JUMP")
                    )

                prev_distance = centroids_distances_sorted[i]['sum_distances']

            self.transforms['original_gray_blurred_edges_contours_centroids_artifact_measure'] = centroids_distances_sorted

            self.transforms['original_gray_blurred_edges_subject_max_space_centroids'] = {
                'x_min': x1_left,
                'x_max': x2_right,
                'y_min': y1_top,
                'y_max': y2_bottom
            }
            self.transforms['original_gray_blurred_edges_subject_min_space_centroids'] = {
                'x_min': x_min,
                'x_max': x_max,
                'y_min': y_min,
                'y_max': y_max
            }

            self.images['original_subject_min_space'] = self.images['original'][
                self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['y_min']: \
                    self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['y_max'],
                self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['x_min']: \
                    self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['x_max']
                ]

            self.images['original_subject_max_space'] = self.images['original'][
                self.transforms['original_gray_blurred_edges_subject_max_space_centroids']['y_min']: \
                    self.transforms['original_gray_blurred_edges_subject_max_space_centroids']['y_max'],
                self.transforms['original_gray_blurred_edges_subject_max_space_centroids']['x_min']: \
                    self.transforms['original_gray_blurred_edges_subject_max_space_centroids']['x_max']
                ]

        return {
            'error': False,
            'image': self.images['original_subject_max_space']
        }

    def detect_empty_space_edge_detection_canny(self, empty_space_detection = "contours"):
        self.debug_print(fr"empty space detection method: {empty_space_detection}")

        x_min, y_min, x_max, y_max = float('inf'), float('inf'), 0, 0

        if empty_space_detection == 'contours':
            self.prepare_edges()
            self.prepare_edge_contours()

            # Find the bounding rectangle of all contours
            for contour in self.transforms['original_gray_blurred_edges_contours']:
                x, y, w, h = cv2.boundingRect(contour)
                x_min = min(x_min, x)
                y_min = min(y_min, y)
                x_max = max(x_max, x + w)
                y_max = max(y_max, y + h)

        elif empty_space_detection == 'centroids':
            res = self.detect_artifacts()
            if res['error']:
                return res

            x_min = self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['x_min']
            x_max = self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['x_max']
            y_min = self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['y_min']
            y_max = self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['y_max']
        else:
            raise ValueError(fr"Invalid empty space detection method")

        # Add padding
        x_min = max(0, x_min - self.args.canny_padding)
        y_min = max(0, y_min - self.args.canny_padding)
        x_max = min(self.images['original'].shape[1], x_max + self.args.canny_padding)
        y_max = min(self.images['original'].shape[0], y_max + self.args.canny_padding)

        self.images['original_subject_min_space_padded'] = self.images['original'][y_min:y_max,x_min:x_max]

        return {
            'error': False,
            'image': self.images['original_subject_min_space_padded']
        }

    def detect_image_rotation_canny_hough(self):
        hough_threshold_initial = hasattr(self.args, 'hough_threshold_initial') and self.args.hough_threshold_initial or 650
        hough_threshold_minimal = hasattr(self.args, 'hough_threshold_minimal') and self.args.hough_threshold_minimal or 450
        if hough_threshold_initial < hough_threshold_minimal:
            raise ValueError(
                fr"Hough threshold initial can't be below minimal, " +
                "got initial [{hough_threshold_initial}], minimal {hough_threshold_minimal}")

        hough_theta_resolution_degrees = float(hasattr(self.args, 'hough_theta_resolution_degrees') and
                                               self.args.hough_theta_resolution_degrees or 1)
        hough_theta_resolution_rad = math.radians(hough_theta_resolution_degrees)

        hough_rho_resolution_pixels = float(hasattr(self.args, 'hough_rho_resolution_pixels') and
                                            self.args.hough_rho_resolution_pixels or 1)
        hough_rho_resolution_pixels_max = float(hasattr(self.args, 'hough_rho_resolution_pixels_max') and
                                                self.args.hough_rho_resolution_pixels_max or 3)
        if hough_rho_resolution_pixels > hough_rho_resolution_pixels_max:
            raise ValueError(
                fr"hough_rho_resolution_pixels can't be above hough_rho_resolution_pixels_max, " +
                "got initial [{hough_rho_resolution_pixels}], max {hough_rho_resolution_pixels_max}")

        self.prepare_edges()

        lines = None
        hough_threshold = hough_threshold_initial
        hough_rho = hough_rho_resolution_pixels

        random.seed()

        # search for lines within the image, trying relaxing parameters a bit if none found
        #
        while lines is None and \
            (hough_threshold >= hough_threshold_minimal or \
             hough_rho <= hough_rho_resolution_pixels_max):

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
            lines = cv2.HoughLines(
                self.images['original_gray_blurred_edges'],
                hough_rho, hough_theta_resolution_rad,
                hough_threshold)

            lines = hough_filter_lines(lines, self.args)

            if lines is None:
                tmp_random = random.randint(1, 2)

                if (hough_threshold >= hough_threshold_minimal and tmp_random == 1) or \
                    (hough_threshold >= hough_threshold_minimal and not(hough_rho <= hough_rho_resolution_pixels_max)):
                    hough_threshold = hough_threshold - 10
                    self.debug_print(fr"selecting Hough parameters: decreased threshold to {hough_threshold}")
                elif (hough_rho <= hough_rho_resolution_pixels_max and tmp_random == 2) or \
                    (hough_rho <= hough_rho_resolution_pixels_max and not (hough_threshold >= hough_threshold_minimal)):
                    hough_rho = hough_rho + 0.1
                    self.debug_print(fr"selecting Hough parameters: increased rho to {hough_rho}")

                if not(hough_rho <= hough_rho_resolution_pixels_max) and not (hough_threshold >= hough_threshold_minimal):
                    self.debug_print(fr"both hough_threshold is below {hough_threshold_minimal} and " +
                        fr"hough_rho above {hough_rho_resolution_pixels_max}, can't continue searching")

        sum_lines = 0
        sum_deviation = 0

        if lines is None:
            return {
                'error': "Can't find lines in the scan",
                'image': self.images['original']
            }

        # edges pictures allowing colored lines
        img_lines = cv2.cvtColor(self.images['original_gray_blurred_edges'], cv2.COLOR_GRAY2BGR)

        for i in range(0, len(lines)):
            rho = lines[i][0][0]
            theta = lines[i][0][1]

            line_deviation = hough_calc_line_deviation(theta)

            sum_lines = sum_lines + 1
            sum_deviation = sum_deviation + line_deviation

            self.debug_print(fr"hough avg deviation: line {i}: rho - {rho}, theta (deg) - " + str(math.degrees(theta)))
            self.debug_print(fr"hough avg deviation: line {i} angle deviation - " + str(math.degrees(line_deviation)) + ", sum_deviation - " + str(math.degrees(sum_deviation)))

            h, w, *_ = img_lines.shape
            max_dim = max(h, w)

            a = math.cos(theta)
            b = math.sin(theta)
            x0 = a * rho
            y0 = b * rho
            pt1 = (int(x0 + max_dim*(-b)), int(y0 + max_dim*(a)))
            pt2 = (int(x0 - max_dim*(-b)), int(y0 - max_dim*(a)))
            cv2.line(img_lines, pt1, pt2, (0,0,255), 1)

            self.debug_print(fr"hough: line {i}: pt1 <-> pt2: {pt1} <-> {pt2}")

        self.images['original_gray_blurred_edges_lines'] = img_lines
        if self.args.debug:
            n = self.variant * 4 + 4
            self.write('original_gray_blurred_edges_lines', '__' + fr"{n:02d}" + '_gray_blurred_edges_lines')

        self.transforms['inclination_angle_radians'] = sum_deviation / sum_lines
        self.debug_print(
            fr"hough rotating by avg_deviation " +
            str(np.rad2deg(self.transforms['inclination_angle_radians'])) +
            " degrees")

        # Rotate the image by the selected angled
        rows, cols = self.images['original'].shape[:2]
        rotation_matrix = cv2.getRotationMatrix2D((cols / 2, rows / 2), np.rad2deg(self.transforms['inclination_angle_radians']), 1)

        self.images['original_rotated'] = cv2.warpAffine(
            src = self.images['original'],
            M = rotation_matrix,
            dsize = (cols, rows),
            borderMode = cv2.BORDER_WRAP)

        return {
            'error': False,
            'image': self.images['original_rotated']
        }


def estimate_jpeg_quality(image):
    """
    Estimate the JPEG quality of an image.
    
    Args:
        image (np.ndarray): The input image.
        
    Returns:
        int: The estimated JPEG quality (0-100).
    """
    if image.dtype != np.uint8:
        raise ValueError(r"Input image must be of type np.uint8")
    
    # Compute the variance of the image
    variance = np.var(image)
    
    # Estimate the JPEG quality based on the variance
    quality = 100 - (variance / 255) * 100
    
    return int(np.clip(quality, 0, 100))

def write_jpeg(filename, filedata):
    cv2.imwrite(filename, filedata, [cv2.IMWRITE_JPEG_QUALITY, 85])

def remove_artifacts(
        image_path,
        img_data,
        destination_dir,
        args,
        dbg_imgn = 0
        ):
    """
    Find the largest area which includes image subject and the largest area of "empty" space around it
    """

    if destination_dir is not None:
        dbg_destination = destination_dir
    else:
        dbg_destination = os.path.dirname(image_path)

    print (str(datetime.datetime.now()) + " " + fr"removing artifacts from {image_path}" + (" (image data)" if img_data is not None else ""))
    print (str(datetime.datetime.now()) + " " + fr"     args.artifacts_discontinuity_threshold: {args.artifacts_discontinuity_threshold}")
    print (str(datetime.datetime.now()) + " " + fr"     args.artifacts_majority_threshold: {args.artifacts_majority_threshold}")

    if img_data is not None:
        # Reuse previously generated image data
        img = img_data
    else:
        # Read the image from the file
        img = cv2.imread(image_path)

    # Convert to grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # Apply Gaussian blur to reduce noise
    blurred = cv2.GaussianBlur(gray, (args.canny_gaussian1, args.canny_gaussian2), 0)

    if args.artifacts_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_artifacts_{dbg_imgn:02d}_blurred.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, blurred)
        print(fr"     DEBUG: saved blurred to: " + out_fn)

    # Perform Canny edge detection
    edges = cv2.Canny(blurred, args.canny_threshold1, args.canny_threshold2)

    if args.artifacts_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_artifacts_{dbg_imgn:02d}_edges.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, edges)
        print(fr"     DEBUG: saved edges to: " + out_fn)

    i = 0
    height, width = edges.shape
    print(fr"height / width: {height} / {width}")

    # Find contours from the edges
    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    print(fr"found " + str(len(contours)) + " contours")

    if len(contours) == 0:
        return img

    if args.artifacts_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_artifacts_{dbg_imgn:02d}_contours.txt", os.path.join(dbg_destination, os.path.basename(image_path)))
        print(fr"     DEBUG: saving contours to: " + out_fn)
        with open(out_fn, "w") as f:
            for contour in contours:
                print(contour, file=f)

    # Extract centroids of all contours
    centroids = []
    centroids_with_annotations = []
    for i in range(len(contours)):
        M = cv2.moments(contours[i])

        # M['m00'] can be zero in a few scenarios:
        #   1. Empty contour: If the contour has no points or is empty, all moments including M['m00'] will be zero.
        #   2. Very small contour: For extremely small contours (e.g., a single pixel), numerical precision issues might lead to M['m00'] being computed as zero.
        #   3. Non-contour input: If the input to cv2.moments() is not a valid contour (e.g., an all-zero array), it may result in zero moments.
        #   4. Binary image with all zeros: If the contour is extracted from a binary image that contains all zeros, M['m00'] will be zero.
        #
        # It's important to note that M['m00'] represents the 0th order moment, which is equivalent
        # to the area of the contour. In most practical cases with valid contours, M['m00'] should be positive.
        # When using moments for further calculations (like finding centroids), it's a good practice
        # to check if M['m00'] is zero to avoid division by zero errors.

        if M['m00'] != 0:
            cx = int(M['m10'] / M['m00'])
            cy = int(M['m01'] / M['m00'])

            centroids.append((cx, cy))

            # 0: {'centroid': (3266, 5983)}
            # 1: {'centroid': (1578, 4523)}
            # 6: {'centroid': (1590, 4522)}
            # 7: {'centroid': (1593, 4515)}
            # 8: {'centroid': (1561, 4515)}
            centroids_with_annotations.append({
                'centroid': (cx,cy),
                'contour_n': i,
                'centroid_n': len(centroids) - 1
                })

    print(fr"got " + str(len(centroids_with_annotations)) + " centroids from " + str(len(contours)) + " contours")

    if len(centroids) < 2:
        return 0  # Not enough centroids to calculate artifact measure

    # Calculate pairwise distances between all centroids
    print (str(datetime.datetime.now()) + " " + fr"calculating distance_matrix for " + str(len(centroids_with_annotations)) + " centroids")
    dist_matrix = distance_matrix(centroids, centroids)

    # For each centroid, calculate the sum of distances to all other centroids
    for i in range(len(centroids)):
        distances = dist_matrix[i]
        centroids_with_annotations[i]['sum_distances'] = np.round(np.sum(distances))

    if args.artifacts_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_artifacts_{dbg_imgn:02d}_centroids.txt", os.path.join(dbg_destination, os.path.basename(image_path)))
        print(fr"     DEBUG: saving centroids to: " + out_fn)
        with open(out_fn, "w") as f:
            for i in range(len(centroids_with_annotations)):
                print(str(i) + ": " + str(centroids_with_annotations[i]), file=f)

    centroids_distances_sorted = sorted(centroids_with_annotations, key=lambda x: x['sum_distances'])

    if args.artifacts_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_artifacts_{dbg_imgn:02d}_centroids_distances_sorted.txt", os.path.join(dbg_destination, os.path.basename(image_path)))
        print(fr"     DEBUG: saving centroids_distances_sorted to: " + out_fn)
        with open(out_fn, "w") as f:
            # header
            print("centroid_n,contour_n,sum_measure,x,y", file=f)

            # data
            for i in range(len(centroids_distances_sorted)):
                print(str(i) + 
                      "," + str(centroids_distances_sorted[i]['contour_n']) + 
                      "," + str(centroids_distances_sorted[i]['sum_distances']) +
                      "," + str(centroids_distances_sorted[i]['centroid'][0]) +
                      "," + str(centroids_distances_sorted[i]['centroid'][1]),
                      file=f)

    _, j = math.modf(len(centroids_distances_sorted) * args.artifacts_majority_threshold)
    if args.artifacts_debug:
        print(fr"     DEBUG: working on the " + str(1 - args.artifacts_majority_threshold) +
              fr" of the biggest areas, from {j} to " + str(len(centroids_distances_sorted) - 1))

    # Find the bounding rectangle of all centroids except artifacts
    x_min, y_min, x_max, y_max = float('inf'), float('inf'), 0, 0

    # find the biggest bounding rect without artifacts (TODO: replace with nearby contours without artifacts - why?)
    x1_left, y1_top, x2_right, y2_bottom = 0, 0, width, height

    prev_distance = None
    jump_centroid = None
    for i in range(len(centroids_distances_sorted)):
        if i < j:
            # can't be an artifact - by definition
            x, y, w, h = cv2.boundingRect(contours[centroids_distances_sorted[i]['contour_n']])
            x_min = min(x_min, x)
            y_min = min(y_min, y)
            x_max = max(x_max, x + w)
            y_max = max(y_max, y + h)        
        else:
            # artifacts_discontinuity_threshold - potential artifacts
            if prev_distance is None:
                prev_distance = centroids_distances_sorted[i]['sum_distances']
            else:
                if jump_centroid is None:
                    if (centroids_distances_sorted[i]['sum_distances'] - prev_distance) / prev_distance > args.artifacts_discontinuity_threshold:
                        jump_centroid = i
                    else:
                        # not an artifact
                        x, y, w, h = cv2.boundingRect(contours[centroids_distances_sorted[i]['contour_n']])
                        x_min = min(x_min, x)
                        y_min = min(y_min, y)
                        x_max = max(x_max, x + w)
                        y_max = max(y_max, y + h)

                if jump_centroid:
                    x, y, w, h = cv2.boundingRect(contours[centroids_distances_sorted[i]['contour_n']])
                    if x + w < x_min:
                        x1_left = max(x + w, x1_left)
                    if x > x_max:
                        x2_right = min(x, x2_right)
                    if y + h < y_min:
                        y1_top = max(y + h, y1_top)
                    if y > y_max:
                        y2_bottom = min(y, y2_bottom)

            prev_distance = centroids_distances_sorted[i]['sum_distances']
            if args.artifacts_debug:
                print(fr"{i}: " +
                    str(centroids_distances_sorted[i]['sum_distances']) +
                    ("" if jump_centroid is None else " - JUMP"))

    # Crop the image
    cropped = img[y1_top:y2_bottom, x1_left:x2_right]

    if args.artifacts_debug:
        print(fr'DEBUG: main picture rect - x_min,x_max,y_min,y_max: {x_min},{x_max},{y_min},{y_max}')
        print(fr'DEBUG: main picture rect w/o artifacts - y1_top:y2_bottom, x1_left:x2_right: {y1_top},{y2_bottom},{x1_left},{x2_right}')
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_artifacts_{dbg_imgn:02d}_no_artifacts.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, cropped)
        print(fr"     DEBUG: saved image without artifacts to: " + out_fn)

    return cropped


def hough_calc_line_deviation(theta):
    line_deviation = 0
    if theta <= (math.pi / 4): # <45°
        line_deviation = theta - 0
    elif theta <= (math.pi / 2): # between 45° and 90°
        line_deviation = theta - math.pi / 2
    elif theta <= (3 * math.pi / 4): # between 90° and 135°
        line_deviation = theta - math.pi / 2
    else: # between 135° and 180°
        line_deviation = theta - math.pi
    return line_deviation

def hough_filter_lines (lines, args):
    """Filter out vertical, horizontal and too inclined lines"""

    if lines is None:
        return None

    tmp_lines = None

    for i in range(0, len(lines)):
        rho = lines[i][0][0]
        theta = lines[i][0][1]

        line_deviation = hough_calc_line_deviation(theta)

        if line_deviation == 0:
            if args.hough_debug:
                print(fr"     DEBUG hough_filter_lines: line {i} is vertical, excluding from sum_deviation calculation")
        elif line_deviation == math.pi / 2:
            if args.hough_debug:
                print(fr"     DEBUG hough_filter_lines: line {i} is horizontal, excluding from sum_deviation calculation")
        elif math.degrees(line_deviation) > 10 or math.degrees(line_deviation) < -10:
            if args.hough_debug:
                print(fr"     DEBUG hough_filter_lines: line {i} is too inclined, excluding from sum_deviation calculation")
        else:
            if tmp_lines is None:
                tmp_lines = []

            tmp_lines.append(lines[i])

    return tmp_lines

def fix_image_rotation_canny_hough(
        image_path,
        img_data,
        destination_dir,
        args):
    
    gaussian1 = hasattr(args, 'canny_gaussian1') and args.canny_gaussian1 or 71
    gaussian2 = hasattr(args, 'canny_gaussian2') and args.canny_gaussian2 or 71
    threshold1 = hasattr(args, 'canny_threshold1') and args.canny_threshold1 or 10
    threshold2 = hasattr(args, 'canny_threshold2') and args.canny_threshold2 or 1
    padding = hasattr(args, 'canny_padding') and args.canny_padding or 50

    hough_threshold_initial = hasattr(args, 'hough_threshold_initial') and args.hough_threshold_initial or 650
    hough_threshold_minimal = hasattr(args, 'hough_threshold_minimal') and args.hough_threshold_minimal or 450
    if hough_threshold_initial < hough_threshold_minimal:
        hough_threshold_initial = hough_threshold_minimal

    hough_theta_resolution_degrees = float(hasattr(args, 'hough_theta_resolution_degrees') and args.hough_theta_resolution_degrees or 1)
    hough_theta_resolution_rad = math.radians(hough_theta_resolution_degrees)

    hough_rho_resolution_pixels = float(hasattr(args, 'hough_rho_resolution_pixels') and args.hough_rho_resolution_pixels or 1)
    hough_rho_resolution_pixels_max = float(hasattr(args, 'hough_rho_resolution_pixels_max') and args.hough_rho_resolution_pixels_max or 3)
    if hough_rho_resolution_pixels > hough_rho_resolution_pixels_max:
        hough_rho_resolution_pixels = hough_rho_resolution_pixels_max

    if destination_dir is not None:
        dbg_destination = destination_dir
    else:
        dbg_destination = os.path.dirname(image_path)

    print (str(datetime.datetime.now()) + " " + fr"fixing rotation (canny + hough) on {image_path}" + (" (image data)" if img_data is not None else ""))
    print (str(datetime.datetime.now()) + " " + fr"    gaussian blur {args.canny_gaussian1}/{args.canny_gaussian2}")
    print (str(datetime.datetime.now()) + " " + fr"    canny threshold1/threshold2/padding {threshold1}/{threshold2}/{padding}")
    print (str(datetime.datetime.now()) + " " + fr"    hough theta_resolution deg/rad {hough_theta_resolution_degrees}/{hough_theta_resolution_rad}")
    print (str(datetime.datetime.now()) + " " + fr"    hough rho_resolution min/max {hough_rho_resolution_pixels}/{hough_rho_resolution_pixels_max}")
    print (str(datetime.datetime.now()) + " " + fr"    hough threshold initial/minimal: {hough_threshold_initial}/{hough_threshold_minimal}")

    if img_data is not None:
        # Reuse previously generated image data
        img = img_data
    else:
        # Read the image from the file
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
    blurred = cv2.GaussianBlur(gray, (args.canny_gaussian1, args.canny_gaussian2), 0)

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

    lines = None
    hough_threshold = hough_threshold_initial
    hough_rho = hough_rho_resolution_pixels

    random.seed()
    # find lines within the image, relaxing parameters
    #
    while lines is None and \
        (hough_threshold >= hough_threshold_minimal or \
        hough_rho <= hough_rho_resolution_pixels_max):

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
        lines = cv2.HoughLines(edges, hough_rho, hough_theta_resolution_rad, hough_threshold)

        if args.hough_debug:
            print(fr"     DEBUG hough: detected lines: " + str(lines is not None and len(lines) or 0))

        lines = hough_filter_lines(lines, args)

        if lines is None:
            tmp_random = random.randint(1, 2)

            if (hough_threshold >= hough_threshold_minimal and tmp_random == 1) or \
                (hough_threshold >= hough_threshold_minimal and not(hough_rho <= hough_rho_resolution_pixels_max)):
                hough_threshold = hough_threshold - 10
                print (str(datetime.datetime.now()) + " " + fr"    decreased threshold to {hough_threshold}")
            elif (hough_rho <= hough_rho_resolution_pixels_max and tmp_random == 2) or \
                (hough_rho <= hough_rho_resolution_pixels_max and not (hough_threshold >= hough_threshold_minimal)):
                print (str(datetime.datetime.now()) + " " + fr"    increased rho to {hough_rho}")
                hough_rho = hough_rho + 0.1

            if not(hough_rho <= hough_rho_resolution_pixels_max) and not (hough_threshold >= hough_threshold_minimal):
                print (str(datetime.datetime.now()) + " " + fr"both hough_threshold is below {hough_threshold_minimal} and " +
                       fr"hough_rho above {hough_rho_resolution_pixels_max}, can't continue searching")

    sum_lines = 0
    sum_deviation = 0

    if lines is not None:
        img_lines = cv2.cvtColor(edges, cv2.COLOR_GRAY2BGR)
        lines = hough_filter_lines(lines, args)

        for i in range(0, len(lines)):
            rho = lines[i][0][0]
            theta = lines[i][0][1]

            line_deviation = hough_calc_line_deviation(theta)

            if args.hough_debug:
                print(fr"     DEBUG hough avg deviation: line {i}: sum_deviation before, line_deviation - {sum_deviation}, {line_deviation}")

            sum_lines = sum_lines + 1
            sum_deviation = sum_deviation + line_deviation

            if args.hough_debug:
                print(fr"     DEBUG hough avg deviation: line {i}: sum_deviation after, sum_lines - {sum_deviation}, {sum_lines}")

            if args.hough_debug:
                print(fr"     DEBUG hough avg deviation: line {i}: rho - {rho}, theta (deg) - " + str(math.degrees(theta)))
                print(fr"     DEBUG hough avg deviation: line {i} angle deviation - " + str(math.degrees(line_deviation)) + ", sum_deviation - " + str(math.degrees(sum_deviation)))

            h, w, *_ = img_lines.shape
            max_dim = max(h, w)

            a = math.cos(theta)
            b = math.sin(theta)
            x0 = a * rho
            y0 = b * rho
            pt1 = (int(x0 + max_dim*(-b)), int(y0 + max_dim*(a)))
            pt2 = (int(x0 - max_dim*(-b)), int(y0 - max_dim*(a)))
            cv2.line(img_lines, pt1, pt2, (0,0,255), 1)

            if args.hough_debug:
                print(fr"     DEBUG hough: line {i}: pt1 <-> pt2: {pt1} <-> {pt2}")

        if args.hough_debug:
            out_fn = re.sub(r"\.jpg", "_canny_04_lines.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
            write_jpeg(out_fn, img_lines)
            print(fr"     DEBUG: saved lines to: " + out_fn)
    else:
        return img

    avg_deviation = sum_deviation / sum_lines
    if args.hough_debug:
        print(fr"     DEBUG hough rotating by avg_deviation " + str(np.rad2deg(avg_deviation)))
    # Rotate the image by the average angle
    rows, cols = img.shape[:2]
    rotation_matrix = cv2.getRotationMatrix2D((cols / 2, rows / 2), np.rad2deg(avg_deviation), 1)
    rotated_image = cv2.warpAffine(
        src = img,
        M = rotation_matrix,
        dsize = (cols, rows),
        borderMode = cv2.BORDER_WRAP)

    if args.hough_debug:
        out_fn = re.sub(r"\.jpg", "_canny_05_rotated.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, rotated_image)
        print(fr"     DEBUG: saved rotated to: " + out_fn)

    return rotated_image

def remove_empty_space_edge_detection_canny(
        image_path,
        img_data,
        destination_dir,
        args,
        dbg_imgn = 0,
        empty_space_detection = "contours"
        ):
    
    padding = hasattr(args, 'canny_padding') and args.canny_padding or 30

    if destination_dir is not None:
        dbg_destination = destination_dir
    else:
        dbg_destination = os.path.dirname(image_path)

    print (str(datetime.datetime.now()) + " " + fr"removing empty space (canny) on {image_path}" + (" (image data)" if img_data is not None else ""))
    print (str(datetime.datetime.now()) + " " + fr"    gaussian blur {args.canny_gaussian1}/{args.canny_gaussian2}")
    print (str(datetime.datetime.now()) + " " + fr"    canny threshold1/threshold2/padding {args.canny_threshold1}/{args.canny_threshold2}/{padding}")

    if img_data is not None:
        # Reuse previously generated image data
        img = img_data
    else:
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
    blurred = cv2.GaussianBlur(gray, (args.canny_gaussian1, args.canny_gaussian2), 0)
    
    if args.canny_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_canny_{dbg_imgn:02d}_blurred.jpg", os.path.join(dbg_destination, os.path.basename(image_path)))
        write_jpeg(out_fn, blurred)
        print(fr"     DEBUG: saved blurred to: " + out_fn)
    
    # Perform Canny edge detection
    edges = cv2.Canny(blurred, args.canny_threshold1, args.canny_threshold2)

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

    if args.canny_debug:
        dbg_imgn += 1
        out_fn = re.sub(r"\.jpg", fr"_canny_{dbg_imgn:02d}_contours.txt", os.path.join(dbg_destination, os.path.basename(image_path)))
        print(fr"     DEBUG: saving contours to: " + out_fn)
        with open(out_fn, "w") as f:
            for contour in contours:
                print(contour, file=f)

    # Find the bounding rectangle of all contours or centroids except artifacts (depending on the method)
    x_min, y_min, x_max, y_max = float('inf'), float('inf'), 0, 0

    if args.canny_debug:
        print(fr"empty space detection method: {empty_space_detection}")

    if empty_space_detection == 'contours':
        # Find the bounding rectangle of all contours
        for contour in contours:
            x, y, w, h = cv2.boundingRect(contour)
            x_min = min(x_min, x)
            y_min = min(y_min, y)
            x_max = max(x_max, x + w)
            y_max = max(y_max, y + h)
    elif empty_space_detection == 'centroids':
        height, width = edges.shape
        print(fr"height / width: {height} / {width}")

        # Extract centroids of all contours
        centroids = []
        centroids_with_annotations = []
        for i in range(len(contours)):
            M = cv2.moments(contours[i])

            # M['m00'] can be zero in a few scenarios:
            #   1. Empty contour: If the contour has no points or is empty, all moments including M['m00'] will be zero.
            #   2. Very small contour: For extremely small contours (e.g., a single pixel), numerical precision issues might lead to M['m00'] being computed as zero.
            #   3. Non-contour input: If the input to cv2.moments() is not a valid contour (e.g., an all-zero array), it may result in zero moments.
            #   4. Binary image with all zeros: If the contour is extracted from a binary image that contains all zeros, M['m00'] will be zero.
            #
            # It's important to note that M['m00'] represents the 0th order moment, which is equivalent
            # to the area of the contour. In most practical cases with valid contours, M['m00'] should be positive.
            # When using moments for further calculations (like finding centroids), it's a good practice
            # to check if M['m00'] is zero to avoid division by zero errors.

            if M['m00'] != 0:
                cx = int(M['m10'] / M['m00'])
                cy = int(M['m01'] / M['m00'])

                centroids.append((cx, cy))

                # 0: {'centroid': (3266, 5983)}
                # 1: {'centroid': (1578, 4523)}
                # 6: {'centroid': (1590, 4522)}
                # 7: {'centroid': (1593, 4515)}
                # 8: {'centroid': (1561, 4515)}
                centroids_with_annotations.append({
                    'centroid': (cx,cy),
                    'contour_n': i,
                    'centroid_n': len(centroids) - 1
                    })

        print(fr"got " + str(len(centroids_with_annotations)) + " centroids from " + str(len(contours)) + " contours")

        if len(centroids) < 2:
            return 0  # Not enough centroids to calculate artifact measure

        
        print (str(datetime.datetime.now()) + " " + fr"calculating distance_matrix for " + str(len(centroids_with_annotations)) + " centroids")
        # Calculate pairwise distances between all centroids
        dist_matrix = distance_matrix(centroids, centroids)

        # For each centroid, calculate the sum of distances to all other centroids
        for i in range(len(centroids)):
            distances = dist_matrix[i]
            centroids_with_annotations[i]['sum_distances'] = np.round(np.sum(distances))

        if args.artifacts_debug:
            dbg_imgn += 1
            out_fn = re.sub(r"\.jpg", fr"_artifacts_{dbg_imgn:02d}_centroids.txt", os.path.join(dbg_destination, os.path.basename(image_path)))
            print(fr"     DEBUG: saving centroids to: " + out_fn)
            with open(out_fn, "w") as f:
                for i in range(len(centroids_with_annotations)):
                    print(str(i) + ": " + str(centroids_with_annotations[i]), file=f)

        centroids_distances_sorted = sorted(centroids_with_annotations, key=lambda x: x['sum_distances'])

        if args.artifacts_debug:
            dbg_imgn += 1
            out_fn = re.sub(r"\.jpg", fr"_artifacts_{dbg_imgn:02d}_centroids_distances_sorted.txt", os.path.join(dbg_destination, os.path.basename(image_path)))
            print(fr"     DEBUG: saving centroids_distances_sorted to: " + out_fn)
            with open(out_fn, "w") as f:
                # header
                print("centroid_n,contour_n,sum_measure,x,y", file=f)

                # data
                for i in range(len(centroids_distances_sorted)):
                    print(str(i) + 
                        "," + str(centroids_distances_sorted[i]['contour_n']) + 
                        "," + str(centroids_distances_sorted[i]['sum_distances']) +
                        "," + str(centroids_distances_sorted[i]['centroid'][0]) +
                        "," + str(centroids_distances_sorted[i]['centroid'][1]),
                        file=f)

        _, j = math.modf(len(centroids_distances_sorted) * args.artifacts_majority_threshold)
        if args.artifacts_debug:
            print(fr"     DEBUG: working on the " + str(1 - args.artifacts_majority_threshold) +
                fr" of the biggest areas, from {j} to " + str(len(centroids_distances_sorted) - 1))

        # find the biggest bounding rect without artifacts (TODO: replace with nearby contours without artifacts)
        x1_left, y1_top, x2_right, y2_bottom = 0, 0, width, height

        prev_distance = None
        jump_centroid = None
        for i in range(len(centroids_distances_sorted)):
            if i < j:
                # can't be an artifact - by definition
                x, y, w, h = cv2.boundingRect(contours[centroids_distances_sorted[i]['contour_n']])
                x_min = min(x_min, x)
                y_min = min(y_min, y)
                x_max = max(x_max, x + w)
                y_max = max(y_max, y + h)        
            else:
                # artifacts_discontinuity_threshold - potential artifacts
                if prev_distance is None:
                    prev_distance = centroids_distances_sorted[i]['sum_distances']
                else:
                    if jump_centroid is None:
                        if (centroids_distances_sorted[i]['sum_distances'] - prev_distance) / prev_distance > args.artifacts_discontinuity_threshold:
                            jump_centroid = i
                        else:
                            # not an artifact
                            x, y, w, h = cv2.boundingRect(contours[centroids_distances_sorted[i]['contour_n']])
                            x_min = min(x_min, x)
                            y_min = min(y_min, y)
                            x_max = max(x_max, x + w)
                            y_max = max(y_max, y + h)

                    if jump_centroid:
                        x, y, w, h = cv2.boundingRect(contours[centroids_distances_sorted[i]['contour_n']])
                        if x + w < x_min:
                            x1_left = max(x + w, x1_left)
                        if x > x_max:
                            x2_right = min(x, x2_right)
                        if y + h < y_min:
                            y1_top = max(y + h, y1_top)
                        if y > y_max:
                            y2_bottom = min(y, y2_bottom)

                prev_distance = centroids_distances_sorted[i]['sum_distances']
                if args.artifacts_debug:
                    print(fr"{i}: " +
                        str(centroids_distances_sorted[i]['sum_distances']) +
                        ("" if jump_centroid is None else " - JUMP"))
    else:
        raise ValueError(r"Invalid empty space detection method")

    # Add padding
    x_min = max(0, x_min - padding)
    y_min = max(0, y_min - padding)
    x_max = min(img.shape[1], x_max + padding)
    y_max = min(img.shape[0], y_max + padding)
    
    if args.canny_debug:
        print(fr'DEBUG: main picture rect - x_min,x_max,y_min,y_max: {x_min},{x_max},{y_min},{y_max}')

    # Crop the image
    cropped = img[y_min:y_max, x_min:x_max]
    
    return cropped

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
    parser.add_argument('--run', type=str, default='', help='mandatory, mode of operation. one of: trim-canny, fix-rotation, remove-artifacts, clean-all, image-info')
    parser.add_argument('--canny-threshold1', type=int, default=10)
    parser.add_argument('--canny-threshold2', type=int, default=1)
    parser.add_argument('--canny-gaussian1', type=int, default=71)
    parser.add_argument('--canny-gaussian2', type=int, default=71)
    parser.add_argument('--canny-padding', type=int, default=100)
    parser.add_argument('--canny-debug', type=bool, default=False)
    parser.add_argument('--hough-debug', type=bool, default=False)
    parser.add_argument('--hough-theta-resolution-degrees', type=float)
    parser.add_argument('--hough-rho-resolution-pixels', type=float, help='width of the detected line - min')
    parser.add_argument('--hough-rho-resolution-pixels-max', type=float, help='width of the detected line - max')
    parser.add_argument('--hough-threshold-initial', type=int, help='number of points in a line required to detect a line - max')
    parser.add_argument('--hough-threshold-minimal', type=int, help='number of points in a line required to detect a line - min')
    parser.add_argument('--copy-source-to-destination', type=bool, default=False)
    parser.add_argument('--skip-existing', type=bool, default=False, help='if destination  exists, do not overwrite')
    parser.add_argument('--artifacts-debug', type=bool, default=False)   
    parser.add_argument('--artifacts-majority-threshold', type=float, default=0.99, help='% of centroids by artifact measure not considered artifacts')
    parser.add_argument('--artifacts-discontinuity-threshold', type=float, default=0.15, help='% of measure jump considered discontinuity')
    parser.add_argument('--classfull', type=bool, default=False)
    parser.add_argument('--debug', type=bool, default=False)

    args = parser.parse_args()

    source_dir = args.source_dir if hasattr(args, 'source_dir') else None
    destination_dir = args.destination_dir if hasattr(args, 'destination_dir') else None
    input_filename = args.filename if hasattr(args, 'filename') else None

    if (args.run not in ["trim-canny", "fix-rotation", "remove-artifacts", "clean-all", "image-info"]):
        parser.print_help()
        print("\n" fr"Need --run with one of: trim-canny, fix-rotation, remove-artifacts, clean-all, image-info" "\n")
        sys.exit(2)

    if args.run == r"image-info":
        with open(input_filename, 'rb') as f:
            # Read the EXIF data
            tags = exifread.process_file(f)
            print(tags)
        img = cv2.imread(input_filename)
        jpeg_quality = estimate_jpeg_quality(img)
        print(f"Estimated JPEG quality: {jpeg_quality}%")
    elif (source_dir is not None and input_filename is not None):
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

                if args.copy_source_to_destination and not os.path.samefile(source_dir, destination_dir):
                    shutil.copy2(os.path.join(source_dir, afn), destination_dir)

                if args.run == r"trim-canny":
                    output_filename = re.sub(r"\.jpg", "_canny_cropped.jpg", os.path.join(destination_dir, afn))

                    if args.skip_existing and (os.path.isfile(output_filename)):
                        print(str(datetime.datetime.now()) + fr"     skipping existing {output_filename}")
                        continue

                    cropped_image = remove_empty_space_edge_detection_canny(
                        image_path = os.path.join(source_dir, afn),
                        img_data = None,
                        args = args,
                        destination_dir = destination_dir)
                    write_jpeg(output_filename, cropped_image)
                    print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")

                if args.run == r"fix-rotation":
                    output_filename = re.sub(r"\.jpg", "_fixed_rotation_cropped.jpg", os.path.join(destination_dir, afn))
                    
                    if args.skip_existing and (os.path.isfile(output_filename)):
                        print(str(datetime.datetime.now()) + fr"     skipping existing {output_filename}")
                        continue

                    rotated_image = fix_image_rotation_canny_hough(
                        image_path = os.path.join(source_dir, afn),
                        args = args,
                        destination_dir = destination_dir)
                    cropped_image = remove_empty_space_edge_detection_canny(
                        image_path = os.path.join(source_dir, afn),
                        img_data = rotated_image,
                        args = args,
                        dbg_imgn = 5,
                        destination_dir = destination_dir)
                    
                    write_jpeg(output_filename, cropped_image)
                    print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")
                
                if args.run == r"clean-all":
                    output_filename = re.sub(r"\.jpg", "_clean_all.jpg", os.path.join(destination_dir, afn))

                    if args.skip_existing and (os.path.isfile(output_filename)):
                        print(str(datetime.datetime.now()) + fr"     skipping existing {output_filename}")
                        continue

                    image_without_artifacts = remove_artifacts(
                        image_path = os.path.join(source_dir, afn),
                        img_data = None,
                        args = args,
                        destination_dir = destination_dir,
                        dbg_imgn = 0)
                    rotated_image = fix_image_rotation_canny_hough(
                        image_path = os.path.join(source_dir, afn),
                        img_data = image_without_artifacts,
                        args = args,
                        destination_dir = destination_dir)
                    cropped_image = remove_empty_space_edge_detection_canny(
                        image_path = os.path.join(source_dir, afn),
                        img_data = rotated_image,
                        args = args,
                        dbg_imgn = 5,
                        destination_dir = destination_dir,
                        empty_space_detection = "centroids")
                    write_jpeg(output_filename, cropped_image)
                    print (str(datetime.datetime.now()) + " " + fr"written to {output_filename}")

        else:
            parser.print_help()
            print("\n" fr"Non-existent directory specified: [{source_dir}]" "\n")
            sys.exit(2)
    elif (input_filename is not None):
        print (str(datetime.datetime.now()) + " " + fr"working on {input_filename}")

        ascan = ScannedPage(input_filename, args = args)

        if args.run == r"remove-artifacts":
            res = ascan.detect_artifacts()
            if res['error']:
                raise ValueError(res['error'])
            else:
                ascan.write('original_subject_max_space')
        if args.run == r"trim-canny":
            res = ascan.detect_empty_space_edge_detection_canny(empty_space_detection = "centroids")
            if (res['error']):
                raise ValueError(res['error'])
            else:
                ascan.write('original_subject_min_space_padded')
        if args.run == r"fix-rotation":
            res = ascan.detect_image_rotation_canny_hough()
            if (res['error']):
                raise ValueError(res['error'])
            else:
                ascan.write('original_rotated')
        if args.run == r"clean-all":
            # rotate (TBD: extend empty padding before rotation)
            res = ascan.detect_image_rotation_canny_hough()
            if (res['error']):
                raise ValueError(res['error'])

            # treated rotated image as original
            ascan_transformed = ScannedPage(input_filename, args = args, variant = 1)
            ascan_transformed.images['original'] = ascan.images['original_rotated']

            # trim rotate image using centroids with artifact detection
            res = ascan_transformed.detect_empty_space_edge_detection_canny(empty_space_detection = "centroids")
            if (res['error']):
                raise ValueError(res['error'])
            else:
                ascan_transformed.write('original_subject_min_space_padded', "_formatted")
    else:
        parser.print_help()
        print("\n" fr"Need either --filename (to process one file) or --source-dir (to process a directory), got none!" "\n")
        sys.exit(2)

if __name__ == "__main__":
    main()
