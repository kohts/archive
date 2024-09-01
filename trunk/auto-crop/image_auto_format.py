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

from skimage.feature import local_binary_pattern
from sklearn.decomposition import PCA
from sklearn.svm import SVC
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
import pickle
import hashlib

def extract_features(filename):
    image = cv2.imread(filename)

    # Convert to grayscale
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    # Apply LBP
    radius = 3
    n_points = 8 * radius
    lbp = local_binary_pattern(gray, n_points, radius, method='uniform')

    # Compute histogram of LBP
    hist, _ = np.histogram(lbp.ravel(), bins=np.arange(0, n_points + 3), range=(0, n_points + 2))

    # Normalize histogram
    hist = hist.astype("float")
    hist /= (hist.sum() + 1e-7)

    img_bytes = image.tobytes()
    md5_hash = hashlib.md5(img_bytes).hexdigest()

    return {
        'hist': hist,
        'filename': filename,
        'md5': md5_hash
    }

def predict_orientation(image_path, pca, svm):
    features = extract_features(image_path)
    features_pca = pca.transform([features['hist']])
    prob = svm.predict_proba(features_pca)[0]
    return "upright" if prob[1] > 0.5 else "upside down", max(prob)

def train_orientation_model(features, labels):
    X = np.array(features)
    y = np.array(labels)

    # Apply PCA
    pca = PCA(n_components=0.95)
    X_pca = pca.fit_transform(X)

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(X_pca, y, test_size=0.2, random_state=42)

    # Train SVM
    svm = SVC(kernel='rbf', probability=True)
    svm.fit(X_train, y_train)

    # Evaluate
    y_pred = svm.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    print(f"Model accuracy: {accuracy}")

    return pca, svm


class TrainingSet:
    def debug_print(self, astr):
        if self.args.debug:
            print (
                str(datetime.datetime.now()) +
                " " +
                astr
                )

    def __init__(self, path, label, args):
        if not os.path.exists(path):
            raise ValueError('Need existing path, got [' + str(path) + ']')
        self.path = path
        self.args = args
        self.label = label

    def extract_features(self):
        features = []
        labels = []

        for afn in os.listdir(self.path):
            filename = os.path.join(self.path, afn)

            if re.search(r"\.features\.pickle$", filename):
                continue

            features_filename = os.path.join(self.path, str(afn + '.features.pickle'))

            features_data = None
            if os.path.exists(features_filename):
                self.debug_print(fr"reading caches features from {features_filename}")
                try:
                    with open(features_filename, 'rb') as f:
                        features_data = pickle.load(f)
                        for el in ('hist', 'md5', 'filename'):
                            if features_data[el] is None:
                                raise ValueError(r"invalid feature file format: no [{}] element".format(el))
                except Exception as e:
                    features_data = None
                    os.remove(features_filename)
                    self.debug_print(fr"broken feature file {features_filename}: {e.args[0]}, removed")

            if features_data is None:
                self.debug_print(fr"extracting features from {filename}")

                features_data = extract_features(filename)

                with open(features_filename, 'wb') as f:
                    pickle.dump(features_data, f)
                self.debug_print(f"Features cached to {features_filename}")

            features.append(features_data['hist'])
            labels.append(self.label)

        self.features = features
        self.labels = labels

class ScannedPage:
    def debug_print(self, astr):
        if self.args.debug:
            print (
                str(datetime.datetime.now()) +
                " [" +
                self.filename_without_ext +
                "] " +
                astr
                )

    def __init__(self,
                 filename,
                 args = defaultdict(lambda:None),
                 variant = 0
                 ):
        if not os.path.isfile(filename):
            raise ValueError(r"Need an image file to proceed, got: [{}] (check if it exists)".format(filename))

        # filename with original scan
        self.filename = filename

        # filename without extension
        if s := re.search(r"^(.+)\.[^\.]+$", os.path.basename(self.filename)):
            self.filename_without_ext = s[1]
        else:
            self.filename_without_ext = self.filename

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

        if args.clean_existing:
            for afn in os.listdir(self.destination_path):
                if afn == os.path.basename(self.filename) or \
                   re.search(str(r"^" + self.filename_without_ext + r"__.+"), afn):
                    os.remove(os.path.join(self.destination_path, afn))
                    self.debug_print(fr"cleaned up [" + os.path.join(self.destination_path, afn) + fr"]")

        if args.copy_source_to_destination and not os.path.samefile(os.path.dirname(self.filename), self.destination_path):
            shutil.copy2(self.filename, self.destination_path)
            self.debug_print(fr"copied original [{self.filename}] to [{self.destination_path}]")

        # multiple original scans with different transformations
        self.variant = variant

    def read(self):
        if self.images['original'] is None:
            self.debug_print(fr"reading {self.filename}")
            self.images['original'] = cv2.imread(self.filename)

    def output_filename(self, image_type, image_suffix = None):
        if image_suffix is None:
            image_suffix = "_" + str(image_type)

        output_filename = re.sub(r"\.jpg",
                                 fr"{image_suffix}.jpg",
                                 os.path.join(self.destination_path, os.path.basename(self.filename)))
        return output_filename

    def write(self, image_type, image_suffix = None):
        if self.written_images[image_type] is not None:
            raise ValueError(r"Image type [{}] has already been written into ".format(image_type) + str(self.written_images[image_type]))

        if self.images[image_type] is None:
            raise ValueError("Requested to write non-existent image type '{}'".format(image_type))

        output_filename = self.output_filename(image_type, image_suffix)

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

    def detect_empty_space_edge_detection_canny(self, empty_space_detection = "centroids"):
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

        self.transforms['original_subject_min_space'] = {
            'x_min': max(0, x_min),
            'y_min': max(0, y_min),
            'x_max': min(self.images['original'].shape[1], x_max),
            'y_max': min(self.images['original'].shape[0], y_max)
        }

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

    def subject_touches_frames(self):
        if self.transforms['original_subject_min_space'] is None:
            raise ValueError("subject_touches_frames requires detect_empty_space_edge_detection_canny to be run first")

        if self.transforms['original_subject_min_space']['x_min'] == 0 or \
           self.transforms['original_subject_min_space']['x_max'] == self.images['original'].shape[1] or \
           self.transforms['original_subject_min_space']['y_min'] == 0 or \
           self.transforms['original_subject_min_space']['y_max'] == self.images['original'].shape[0]:
            return True
        else:
            return False
        
    def enough_space_to_rotate(self):
        if self.transforms['original_subject_min_space'] is None:
            raise ValueError("enough_space_to_rotate requires detect_empty_space_edge_detection_canny to be run first")

        longest_side = max(
            self.transforms['original_subject_min_space']['x_max'] - self.transforms['original_subject_min_space']['x_min'],
            self.transforms['original_subject_min_space']['y_max'] - self.transforms['original_subject_min_space']['y_min']
        )

        if self.transforms['original_subject_min_space']['x_max'] + longest_side > self.images['original'].shape[1]:

            diff = self.transforms['original_subject_min_space']['x_max'] + longest_side - self.images['original'].shape[1]

            self.images['temp'] = self.images['original']
            while self.images['temp'].shape[1] < self.images['original'].shape[1] + diff:
                cut_cols = min(
                    self.images['original'].shape[1] + diff - self.images['temp'].shape[1],
                    self.transforms['original_subject_min_space']['x_min']
                    )

                self.debug_print(fr"extending to the right by {cut_cols} pixel(s)")

                # cut out the first {cut_cols} columns, returned as 3D array
                # (Y ranges from 0 to height, X ranges from 0 to {cut_cols}, all 3 color channels))
                first_cols_3d = np.fliplr(self.images['original'][:,0:cut_cols,:])

                # extend original image with the required number of columns
                self.images['temp'] = np.hstack((self.images['temp'], first_cols_3d))

            return {
                'error': False,
                'image': self.images['temp']
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
    parser.add_argument('--source-dir', type=str, default=None)
    parser.add_argument('--destination-dir', type=str, default=None)
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
    parser.add_argument('--skip-existing', type=bool, default=False, help='if destination exists, do not overwrite')
    parser.add_argument('--clean-existing', type=bool, default=False, help='if destination image and/or related debug exists, clean it')
    parser.add_argument('--artifacts-debug', type=bool, default=False)   
    parser.add_argument('--artifacts-majority-threshold', type=float, default=0.99, help="%% of centroids by artifact measure not considered artifacts")
    parser.add_argument('--artifacts-discontinuity-threshold', type=float, default=0.15, help="%% of measure jump considered discontinuity")
    parser.add_argument('--debug', type=bool, default=False)
    parser.add_argument('--train-path-up', type=str, default='')
    parser.add_argument('--train-path-down', type=str, default='')
    parser.add_argument('--check-orientation', type=str, default='')
    args = parser.parse_args()

    if (args.run not in [
        "trim-canny", "fix-rotation", "remove-artifacts", "clean-all", "enough-space-to-rotate",
        "image-info", "",
        "train-model"
        ]):
        parser.print_help()
        print("\n" fr"Need --run with one of: trim-canny, fix-rotation, remove-artifacts, clean-all, image-info" "\n")
        sys.exit(2)

    if args.run == r"train-model":
        ats_up, ats_down = None, None
        if args.train_path_up:
            ats_up = TrainingSet(args.train_path_up, "up", args)
            ats_up.extract_features()
        if args.train_path_down:
            ats_down = TrainingSet(args.train_path_down, "down", args)
            ats_down.extract_features()

        features = ats_up.features + ats_down.features
        labels = ats_up.labels + ats_down.labels
        pca, svm = train_orientation_model(features, labels)

        orientation, confidence = predict_orientation(args.check_orientation, pca, svm)
        print(f"The image {args.check_orientation} is likely {orientation} with {confidence:.2f} confidence.")

        sys.exit(0)

    if args.run == r"image-info":
        with open(args.filename, 'rb') as f:
            # Read the EXIF data
            tags = exifread.process_file(f)
            print(tags)
        img = cv2.imread(args.filename)
        jpeg_quality = estimate_jpeg_quality(img)
        print(f"Estimated JPEG quality: {jpeg_quality}%")
        sys.exit(0)

    if (args.source_dir is not None and args.filename is not None):
        parser.print_help()
        print("\n" fr"Choose either --filename (to process one file) or --source-dir (to process a directory), not both!" "\n")
        sys.exit(2)
    if args.source_dir is not None and args.destination_dir is None:
        parser.print_help()
        print("\n" fr"Specifying --source-dir implies specifying --destination-dir!" "\n")
        sys.exit(2)
    if args.source_dir is not None and not os.path.isdir(args.source_dir):
        parser.print_help()
        print("\n" fr"Non-existent directory specified: [{args.source_dir}]" "\n")
        sys.exit(2)

    files_to_process = []

    if args.source_dir is not None:
        for afn in os.listdir(args.source_dir):
            files_to_process.append({
                'input_filename': os.path.join(args.source_dir, afn),
                'destination_dir': args.destination_dir
            })
    if args.filename is not None:
        files_to_process.append({
            'input_filename': args.filename,
            'destination_dir': args.destination_dir if args.destination_dir is not None else os.path.dirname(args.filename)
        })
    if len(files_to_process) < 1:
        parser.print_help()
        print("\n" fr"No files to process: need either --filename (to process one file) or --source-dir (to process a directory), got none!" "\n")
        sys.exit(2)

    for afile in files_to_process:
        args.destination_dir = afile['destination_dir']
        input_filename = afile['input_filename']

        check_and_create_destination(args.destination_dir)

        print (str(datetime.datetime.now()) + " " + fr"working on {input_filename}, saving to {args.destination_dir}")

        ascan = ScannedPage(input_filename, args = args)

        if args.run == r"enough-space-to-rotate":
            res = ascan.detect_empty_space_edge_detection_canny()
            if (res['error']):
                raise ValueError(res['error'])
            
            res = ascan.enough_space_to_rotate()
            if (res['error']):
                raise ValueError(res['error'])

            ascan.write('temp')
        if args.run == r"remove-artifacts":
            if args.skip_existing and os.path.isfile(ascan.output_filename('original_subject_max_space')):
                print(str(datetime.datetime.now()) + fr" skipping existing " + str(ascan.output_filename('original_subject_max_space')))
                continue

            res = ascan.detect_artifacts()
            if res['error']:
                raise ValueError(res['error'])
            else:
                ascan.write('original_subject_max_space')
        if args.run == r"trim-canny":
            if args.skip_existing and os.path.isfile(ascan.output_filename('original_subject_min_space_padded')):
                print(str(datetime.datetime.now()) + fr" skipping existing " + str(ascan.output_filename('original_subject_min_space_padded')))
                continue

            res = ascan.detect_empty_space_edge_detection_canny()
            if (res['error']):
                raise ValueError(res['error'])
            else:
                ascan.write('original_subject_min_space_padded')
        if args.run == r"fix-rotation":
            if args.skip_existing and os.path.isfile(ascan.output_filename('original_rotated')):
                print(str(datetime.datetime.now()) + fr" skipping existing " + str(ascan.output_filename('original_rotated')))
                continue

            res = ascan.detect_image_rotation_canny_hough()
            if (res['error']):
                raise ValueError(res['error'])
            else:
                ascan.write('original_rotated')
        if args.run == r"clean-all":
            if args.skip_existing and os.path.isfile(ascan.output_filename('original_subject_min_space_padded',  "_formatted")):
                print(str(datetime.datetime.now()) + fr" skipping existing " + str(ascan.output_filename('original_subject_min_space_padded',  "_formatted")))
                continue

            # check if the original image subject "touches" side of the picture:
            # if it doest - can't rotate it
            res = ascan.detect_empty_space_edge_detection_canny()
            if (res['error']):
                raise ValueError(res['error'])

            if not ascan.subject_touches_frames():
                ascan.debug_print(fr"subject doesn't touch the frame, can apply rotation")

                # rotate (TBD: extend empty padding before rotation)
                res = ascan.detect_image_rotation_canny_hough()
                if (res['error']):
                    raise ValueError(res['error'])

                # treated rotated image as original
                ascan_transformed = ScannedPage(input_filename, args = args, variant = 1)
                ascan_transformed.images['original'] = ascan.images['original_rotated']

                # trim rotate image using centroids with artifact detection
                res = ascan_transformed.detect_empty_space_edge_detection_canny()
                if (res['error']):
                    raise ValueError(res['error'])

                ascan = ascan_transformed

            ascan.write('original_subject_min_space_padded', "_formatted")

if __name__ == "__main__":
    main()
