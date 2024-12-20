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
from scipy.spatial import distance

import exifread

from skimage.draw import line
from skimage.feature import local_binary_pattern
from sklearn.decomposition import PCA
from sklearn.svm import SVC
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

from sklearn.preprocessing import MinMaxScaler

import pickle
import hashlib

import inspect
import colorsys

import gzip

MAX_ROTATION_ANGLE_DEGREES=10

def compress_file(input_path, output_path=None, chunk_size=1024*1024):  # 1MB chunks
    """
    Compress a file using gzip compression with efficient chunked processing.

    Args:
        input_path (str): Path to the file to compress
        output_path (str, optional): Path for compressed file. If None, adds '.gz' to input path
        chunk_size (int): Size of chunks to read/write in bytes (default 1MB)

    Returns:
        str: Path to the compressed file
    """
    # If no output path specified, add .gz extension to input path
    if output_path is None:
        output_path = input_path + '.gz'

    try:
        with open(input_path, 'rb') as file_in:
            with gzip.open(output_path, 'wb', compresslevel=9) as file_out:
                while True:
                    chunk = file_in.read(chunk_size)
                    if not chunk:
                        break
                    file_out.write(chunk)

        return output_path

    except Exception as e:
        # Clean up partial output file if there's an error
        if os.path.exists(output_path):
            os.remove(output_path)
        raise Exception(f'Compression failed: {str(e)}')


def find_bounding_rect_of_contours(contours):
    # Combine all contours into a single array of points
    all_points = np.vstack([cnt.reshape(-1, 2) for cnt in contours])

    # Find the minimum and maximum x and y coordinates
    x_min = np.min(all_points[:, 0])
    y_min = np.min(all_points[:, 1])
    x_max = np.max(all_points[:, 0])
    y_max = np.max(all_points[:, 1])

    # Calculate width and height
    width = x_max - x_min
    height = y_max - y_min

    # Return the bounding rectangle in the format (x, y, width, height)
    return {
        'x_min': int(x_min),
        'y_min': int(y_min),
        'width': int(width),
        'height': int(height)
    }

def generate_distinct_colors(n):
    colors = []
    for i in range(n):
        hue = i / n
        saturation = 0.9
        value = 0.9
        rgb = tuple(int(x * 255) for x in colorsys.hsv_to_rgb(hue, saturation, value))
        colors.append(rgb)
    return colors

def get_caller_name():
    current_frame = inspect.currentframe()
    caller_frame = current_frame.f_back

    if caller_frame is not None and caller_frame.f_back is not None:
        caller_frame = caller_frame.f_back

    if caller_frame is not None:
        if 'self' in caller_frame.f_locals:
            # It's a method
            return f"{caller_frame.f_locals['self'].__class__.__name__}.{caller_frame.f_code.co_name}"
        else:
            # It's a function
            return caller_frame.f_code.co_name
    return "<unknown>"

def line_contour(x1, y1, x2, y2):
    # Calculate the number of points based on the maximum distance
    num_points = int(max(abs(x2 - x1), abs(y2 - y1))) + 1

    # Generate equally spaced points along the x and y axes
    x_coords = np.linspace(x1, x2, num_points, dtype=np.int32)
    y_coords = np.linspace(y1, y2, num_points, dtype=np.int32)

    # Combine the x and y coordinates into an array of (x, y) pairs
    coordinates = np.stack((x_coords, y_coords), axis=1)

    return np.reshape(coordinates, (len(coordinates), 1, 2))

def shortest_path_between_contours(contour1, contour2):
    # Convert contours to NumPy arrays
    contour1 = np.array(contour1).reshape(-1, 2)
    contour2 = np.array(contour2).reshape(-1, 2)

    # Calculate pairwise distances between contour points
    dist_matrix = distance.cdist(contour1, contour2)

    # Find the minimum distance and corresponding points
    min_dist_idx = np.unravel_index(np.argmin(dist_matrix), dist_matrix.shape)
    min_dist = dist_matrix[min_dist_idx]
    min_point1 = tuple(contour1[min_dist_idx[0]])
    min_point2 = tuple(contour2[min_dist_idx[1]])

    return min_point1, min_point2, round(min_dist,0)

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

def average_color(img):
    # Calculate the number of pixels
    num_pixels = np.prod(img.shape[:2], dtype=np.int64)

    if num_pixels < 1:
        return (np.array([0, 0, 0], dtype=np.uint8), 0)

    # Calculate the sum of each channel
    channel_sums = np.sum(img, axis=(0, 1), dtype=np.int64)

    # Calculate the average
    average_color = channel_sums / num_pixels

    # Round to integers
    average_color = np.round(average_color).astype(int)

    return (average_color, num_pixels)

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

    logged_run = False
    cleaned_files = defaultdict(lambda:None)
    orig_files = defaultdict(lambda:None)

    def batch_log(self, msg):
        if not hasattr(self, 'destination_path'):
            raise ValueError('object has not been initialized as expected: destination_path is not defined')

        with open(os.path.join(self.destination_path, '.conversion.log'), 'a') as f:
            f.write(
                str(datetime.datetime.now()) + " [" +
                self.filename_without_ext + "] " +
                str(msg) + '\n'
                )
        self.debug_print(msg)

    def debug_print(self, astr):
        if not hasattr(self, 'destination_path'):
            raise ValueError('object has not been initialized as expected: destination_path is not defined')

        dbg_msg = str(datetime.datetime.now()) + " " \
            "[" + self.filename_without_ext + "] " + \
            "[" + get_caller_name() + "] " + \
            astr

        if self.args.debug_log is not None:
            with open(os.path.join(self.destination_path, '.debug.log'), 'a') as f:
                f.write(dbg_msg + '\n')

        if self.args.debug:
            print (dbg_msg)

    def __init__(self,
                 filename,
                 args = defaultdict(lambda:None)
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

        createdTargetDir = False
        if hasattr(args, 'destination_dir'):
            if (not os.path.isdir(args.destination_dir)):
                directory = Path(args.destination_dir)
                try:
                    directory.mkdir(parents=True, exist_ok=True)
                    createdTargetDir = True
                except Exception as e:
                    raise ValueError(r"An error occurred while creating directory {}: ".format(args.destination_dir) + str(e))
            self.destination_path = args.destination_dir
        else:
            self.destination_path = os.path.dirname(self.filename)

        if createdTargetDir:
            self.batch_log(fr"created target dir: {args.destination_dir}")
        if not ScannedPage.logged_run:
            self.batch_log('started as: ' + ' '.join(sys.argv))
            ScannedPage.logged_run = True

        if args.clean_existing and ScannedPage.cleaned_files[self.filename] is None:
            destination_same_as_source = self.destination_path == os.path.dirname(self.filename)
            for afn in os.listdir(self.destination_path):
                if (afn == os.path.basename(self.filename) and not destination_same_as_source) or \
                    re.search(str(r"^" + self.filename_without_ext + r"__.+"), afn) or \
                    re.search(str(r"^" + self.filename_without_ext + r"_formatted.jpg"), afn):

                    cleaned_path = os.path.join(self.destination_path, afn)
                    os.remove(cleaned_path)
                    self.debug_print(fr"cleaned up [{cleaned_path}]")

            # clean destination once per run
            ScannedPage.cleaned_files[self.filename] = True

        self.debug_counter = 0
        for afn in os.listdir(self.destination_path):
            if re.search(str(r"^" + self.filename_without_ext + r"__.+"), afn):
                self.debug_counter += 1

        if args.copy_source_to_destination and not os.path.samefile(os.path.dirname(self.filename), self.destination_path) and \
            ScannedPage.orig_files[self.filename] is None:
            shutil.copy2(self.filename, self.destination_path)
            self.debug_print(fr"copied original [{self.filename}] to [{self.destination_path}]")

            # copy original file once per run
            ScannedPage.orig_files[self.filename] = True


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

    def write(self, image_type, image_suffix = None, debug = True):
        if debug:
            if self.args.debug_no_intermediate_images:
                return

            debug_suffix = '__' + fr"{self.debug_counter:02d}"
            self.debug_counter += 1
            if image_suffix is not None:
                image_suffix = debug_suffix + image_suffix
        else:
            if self.written_images[image_type] is not None:
                raise ValueError(r"Image type [{}] has already been written into ".format(image_type) + str(self.written_images[image_type]))

        if self.images[image_type] is None:
            raise ValueError("Requested to write non-existent image type '{}'".format(image_type))

        output_filename = self.output_filename(image_type, image_suffix)

        self.debug_print(fr"writing {image_type} to {output_filename} jpeg quality {self.args.jpeg_quality}")
        write_jpeg(output_filename, self.images[image_type], self.args.jpeg_quality)
        self.written_images[image_type] = output_filename

    def prepare_edges(self, gaussian_kernel = None):
        if self.images['original'] is None:
            self.read()

        # Original image converted to grayscale
        if self.images['original_gray'] is None:
            self.images['original_gray'] = cv2.cvtColor(self.images["original"], cv2.COLOR_BGR2GRAY)
            if self.args.debug:
                self.write('original_gray', '_gray')

        # Redo blur and edge detection if gaussian_kernel has been redefined explicitely

        # Original image converted to grayscale and blurred
        if self.images['original_gray_blurred'] is None or gaussian_kernel is not None:
            if gaussian_kernel is None:
                gaussian_kernel = (
                    self.args.canny_gaussian or self.args.canny_gaussian1,
                    self.args.canny_gaussian or self.args.canny_gaussian2
                    )

            # Apply Gaussian blur to reduce noise
            self.images['original_gray_blurred'] = cv2.GaussianBlur(
                self.images['original_gray'],
                gaussian_kernel,
                0)
            if self.args.debug:
                self.write('original_gray_blurred', '_gray_blurred')

        if self.images['original_gray_blurred_edges'] is None or gaussian_kernel is not None:
            # Perform Canny edge detection
            self.images['original_gray_blurred_edges'] = cv2.Canny(
                self.images['original_gray_blurred'],
                self.args.canny_threshold1,
                self.args.canny_threshold2)
            if self.args.debug:
                self.write('original_gray_blurred_edges', '_gray_blurred_edges')

    def prepare_edge_contours(self, force = False):
        if self.transforms['original_gray_blurred_edges_contours'] is None or force:
            contours, _ = cv2.findContours(self.images['original_gray_blurred_edges'], cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            self.transforms['original_gray_blurred_edges_contours'] = contours
            self.debug_print(fr"Got [" + str(len(self.transforms['original_gray_blurred_edges_contours'])) + "] contours from edges")

    def prepare_dilated_image(self):
        if self.images['original_gray_blurred_edges_dilated'] is None:
            kernel = np.ones((self.args.dilation_kernel_h, self.args.dilation_kernel_w), np.uint8)
            dilated_image = cv2.dilate(self.images['original_gray_blurred_edges'], kernel)

            self.images['original_gray_blurred_edges_dilated'] = dilated_image
            if self.args.debug:
                self.write('original_gray_blurred_edges_dilated', '_gray_blurred_dilated')

    def prepare_edge_contours_centroids(self, force = False):
        if self.transforms['original_gray_blurred_edges_contours_centroids'] is None or force:

            GM = cv2.moments(self.images['original_gray_blurred_edges'])
            self.debug_print(fr"global moment: {GM}")

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

    def dilated_image_min_distance(self):
        self.prepare_edges()
        self.prepare_edge_contours()

        # can't continue the transform
        if len(self.transforms['original_gray_blurred_edges_contours']) < 55:
            return {
                'error': "Blank image"
            }

        self.prepare_dilated_image()

        contours2, _ = cv2.findContours(self.images['original_gray_blurred_edges_dilated'], cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        self.debug_print(fr"contours in dilated image: " + str(len(contours2)))

        contours_distances = []
        for i, c1 in enumerate(contours2):
            for j, c2 in enumerate(contours2):
                _, _, distance = shortest_path_between_contours(c1,c2)
                self.debug_print(fr"contour {i} len {len(c1)}, contour {j} len {len(c2)} dist {distance}")

                contours_distances.append(
                    (i,j,distance,len(c1),len(c2),cv2.contourArea(c1),cv2.contourArea(c2))
                )

        if self.args.artifacts_debug:
            debug_suffix = '__' + fr"{self.debug_counter:02d}"
            self.debug_counter += 1

            output_filename = re.sub(
                r"\.jpg",
                fr"{debug_suffix}_contours_min_distances.txt",
                os.path.join(self.destination_path, os.path.basename(self.filename))
                )

            self.debug_print(fr"saving contours_distances to: " + output_filename)
            with open(output_filename, "w") as f:
                # header
                print("c1_n,c2_n,min_distance,c1_len,c2_len,c1_area,c2_area", file=f)

                # data
                for i in range(len(contours_distances)):
                    print(str(contours_distances[i][0]) +
                        "," + str(contours_distances[i][1]) +
                        "," + str(contours_distances[i][2]) +
                        "," + str(contours_distances[i][3]) +
                        "," + str(contours_distances[i][4]) +
                        "," + str(contours_distances[i][5]) +
                        "," + str(contours_distances[i][6]),
                        file=f)

    def dilated_image_contours_loneliness(self, bgcolor):
        self.prepare_edges()
        self.prepare_edge_contours()

        # can't continue the transform
        if len(self.transforms['original_gray_blurred_edges_contours']) < 55:
            return {
                'error': "Blank image"
            }

        self.prepare_dilated_image()
        contours2, _ = cv2.findContours(self.images['original_gray_blurred_edges_dilated'], cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        distances = np.zeros((len(contours2), len(contours2)))
        areas = np.zeros((len(contours2)))
        loneliness = np.zeros((len(contours2)))

        for i, c1 in enumerate(contours2):
            for j, c2 in enumerate(contours2):
                _, _, distance = shortest_path_between_contours(c1, c2)
                # self.debug_print(fr"contour distance {i} <-> {j}: {distance}")
                distances[i, j] = distance
                distances[j, i] = distance
            areas[i] = cv2.contourArea(c1)
            self.debug_print(fr"contour {i} len {len(c1)}, area {areas[i]}")

        # filter out all the contours which do not affect bounding rectangle of the overall picture,
        # effectively leaving only those contours which are adjacent to the side of the picture.
        side_contours = []
        side_contours_area_diff = []
        overall_bounding_rect = find_bounding_rect_of_contours(contours2)

        for i, c1 in enumerate(contours2):
            tmp_contours2 = [c2 for j, c2 in enumerate(contours2) if i != j]
            if len(tmp_contours2) == 0:
                continue

            tmp_bounding_rect = find_bounding_rect_of_contours(tmp_contours2)

            area_diff = (
                1 -
                (tmp_bounding_rect['width'] * tmp_bounding_rect['height']) /
                (overall_bounding_rect['width'] * overall_bounding_rect['height'])
            )
            self.debug_print(fr"contour {i} - area diff {area_diff}")

            side_contours.append(i)
            side_contours_area_diff.append(area_diff)

        lone_side_contours = []

        # filter out all the side contours of approx. the same size
        # which affect bounding rectangle are on the same scale,
        # meaning these contours are most probably similar one to another
        # and we need manual validation anyway
        #
        for i in range(len(side_contours)):
            similar_contours = [j
                for j, area_diff in enumerate(side_contours_area_diff)
                    if
                        math.fabs(area_diff - side_contours_area_diff[i]) < 0.05 and
                        areas[i] / areas[j] > 0.1 and
                        areas[i] / areas[j] < 10
                ]
            if len(similar_contours) == 1:
                self.debug_print(fr"contour {side_contours[i]} solely decreases the area by {side_contours_area_diff[i]} +/- 5%")
                lone_side_contours.append(side_contours[i])
            else:
                self.debug_print(fr"contour {side_contours[i]} has {len(similar_contours)} similar side contours")

        self.images['original_outliers_removed'] = self.images['original'].copy()
        outliers = []

        if len(contours2) < 4:
            self.debug_print(fr"detected too little contours [{len(contours2)}], applying simple area/distance filtration algorithm")
            max_area_val = np.max(areas)
            max_area_pos = np.argmax(areas)

            self.debug_print(fr"biggest contour {max_area_pos}, area {max_area_val}")

            for i, c1 in enumerate(contours2):
                self.debug_print(fr"contour {i} area {areas[i]}, distance to biggest {max_area_pos}: {distances[i, max_area_pos]}")
                if areas[i] < 0.01 * max_area_val and distances[i, max_area_pos] > math.sqrt(max_area_val) * 0.05 and i in lone_side_contours:
                    self.debug_print(
                        fr"OUTLIER: " +
                        fr"contour {i} area {areas[i]} < 0.01 * {max_area_val} [{0.01 * max_area_val}] and " +
                        fr"distance from {i} to {max_area_pos} {distances[i, max_area_pos]} > sqrt({max_area_val})*0.1 [{math.sqrt(max_area_val) * 0.1}]"
                        )
                    outliers.append([i,c1])
        else:
            scaler = MinMaxScaler()
            #normalized_distances = scaler.fit_transform(np.sort(distances,0))
            normalized_distances = scaler.fit_transform(np.sort(distances,1).flatten().reshape(-1,1)).reshape(distances.shape)
            normalized_area = scaler.fit_transform(areas.reshape(-1, 1))

            k_neighbours = []
            if self.args.shortest_path_exponential:
                for i, distances in enumerate(normalized_distances):
                    # if i == 0:
                    #     k_neighbours.append(0)
                    #     continue

                    distance_scaled = distances[1] * 0.9 + distances[2] * 0.09 + distances[3] * 0.01
                    self.debug_print(fr"kNN {i} {distances[1]} * 0.9 + {distances[2]} * 0.09 + {distances[3]} * 0.01")

                    k_neighbours.append(distance_scaled)
            else:
                k_neighbours = np.sum(normalized_distances[:4,:], axis=0) / 3

            w_neighbours = 0.7
            w_area = 0.3

            for i, c1 in enumerate(contours2):
                loneliness[i] = w_neighbours * k_neighbours[i] + w_area * (1 - normalized_area[i][0])
                self.debug_print(fr"{i} loneliness {loneliness[i]} = {w_neighbours} * {k_neighbours[i]} + {w_area} * (1 - {normalized_area[i][0]})")
                if loneliness[i] > self.args.loneliness_threshold and i in lone_side_contours:
                    self.debug_print(fr"OUTLIER: contour {i}")
                    outliers.append([i,c1])

        shaded_areas = 0
        if len(outliers) < 7:
            for c in outliers:
                self.debug_print(fr"shading contour {c[0]}")
                cv2.drawContours(self.images['original_outliers_removed'], [c[1]], 0, bgcolor, -1)
                shaded_areas = shaded_areas + 1
        else:
            return {
                'error': 'Too many small contours',
            }

        if self.args.debug:
            self.dilated_image_contours_debug()
            self.write('original_outliers_removed', '_original_outliers_removed')

        return {
            'error': False,
            'shaded_areas': shaded_areas
        }


    def dilated_image_contours_debug(self):
        self.prepare_edges()
        self.prepare_edge_contours()

        # can't continue the transform
        if len(self.transforms['original_gray_blurred_edges_contours']) < 55:
            return {
                'error': "Blank image"
            }

        self.prepare_dilated_image()

        contours2, _ = cv2.findContours(self.images['original_gray_blurred_edges_dilated'], cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        self.debug_print(fr"contours in dilated image: " + str(len(contours2)))

        out_image = self.images['original'].copy()
        colors = generate_distinct_colors(len(contours2))
        min_paths = defaultdict(lambda:None)
        min_path_contours = defaultdict(lambda:None)

        bounding_rect = find_bounding_rect_of_contours(contours2)

        for i, c1 in enumerate(contours2):
            self.debug_print(fr"contour {i}, points {len(c1)}, color {colors[i]}")
            cv2.drawContours(out_image, [c1], -1, colors[i], 5)
            cv2.putText(out_image, fr"{i}", c1[0][0], cv2.FONT_HERSHEY_SIMPLEX, 2, colors[i], 5)

            if self.args.show_contour_shortest_paths is not None and i == self.args.show_contour_shortest_paths:
                total = 0
                labels = []
                for j, c2 in enumerate(contours2):
                    if min_paths[i] is None:
                        min_paths[i] = defaultdict(lambda:None)
                        min_path_contours[i] = defaultdict(lambda:None)

                    if min_paths[i][j] is None:
                        min_paths[i][j] = tuple(shortest_path_between_contours(contours2[i], contours2[j]))
                        self.debug_print(fr"min_path {i} <--- {min_paths[i][j]} ---> {j}")

                        min_path_contours[i][j] = line_contour(
                            min_paths[i][j][0][0],
                            min_paths[i][j][0][1],
                            min_paths[i][j][1][0],
                            min_paths[i][j][1][1]
                            )

                        middle_x = int((min_paths[i][j][0][0] + min_paths[i][j][1][0]) / 2)
                        middle_y = int((min_paths[i][j][0][1] + min_paths[i][j][1][1]) / 2)
                        point = np.array([middle_x, middle_y], dtype=np.uint32)

                        cv2.putText(out_image, str(int(min_paths[i][j][2])), point, cv2.FONT_HERSHEY_SIMPLEX, 2, (0,0,0), 5)
                        cv2.drawContours(out_image, min_path_contours[i][j], -1, (0,0,0), 5)

                        labels.append((int(min_paths[i][j][2]), j))
                        cv2.putText(out_image, fr"{j}: {str(int(min_paths[i][j][2]))}", (bounding_rect['x_min'] + bounding_rect['width'] + 200, bounding_rect['y_min'] + j * 70), cv2.FONT_HERSHEY_SIMPLEX, 2, (0,0,0), 5)
                        total = total + int(min_paths[i][j][2])

                labels_sorted = sorted(labels, key=lambda x: x[0])
                for j, t in enumerate(labels_sorted):
                    cv2.putText(out_image, fr"{t[1]}: {str(t[0])}", (bounding_rect['x_min'] + bounding_rect['width'] + 600, bounding_rect['y_min'] + j * 70), cv2.FONT_HERSHEY_SIMPLEX, 2, (0,0,0), 5)

                cv2.putText(out_image, fr"total: {total}", (bounding_rect['x_min'] + bounding_rect['width'] + 200, bounding_rect['y_min'] + len(contours2) * 70 + 1 * 70), cv2.FONT_HERSHEY_SIMPLEX, 2, (0,0,0), 5)

        if self.args.fill_contour is not None:
            cv2.fillConvexPoly(out_image, contours2[self.args.fill_contour], (0,255,0), )

        self.images['dilated_image_contours_debug'] = out_image
        if self.args.debug:
            self.write('dilated_image_contours_debug', '_dilated_image_contours_debug')

        return {
            'error': False,
            'image': self.images['dilated_image_contours_debug']
        }

    def detect_artifacts(self):
        # do not run twice for the same image
        if self.transforms['original_gray_blurred_edges_contours_centroids_artifact_measure'] is not None:
            return {
                'error': False,
                'image': self.images['original_subject_max_space']
            }

        current_gaussian = [
            self.args.canny_gaussian or self.args.canny_gaussian1,
            self.args.canny_gaussian or self.args.canny_gaussian2
            ]
        centroids_count = math.inf

        while centroids_count > 20_000:
            self.prepare_edges(gaussian_kernel = current_gaussian)
            self.prepare_edge_contours(force = True)

            # can't continue the transform
            if len(self.transforms['original_gray_blurred_edges_contours']) < 55:
                return {
                    'error': "Blank image"
                }

            self.prepare_edge_contours_centroids(force = True)

            if len(self.transforms['original_gray_blurred_edges_contours_centroids']) < 2:
                return {
                    'error': "Can't find enough centroids to calculate artifact measure",
                    'image': self.images['original']
                }

            centroids_count = len(self.transforms['original_gray_blurred_edges_contours_centroids'])

            if centroids_count > 20_000:
                current_gaussian[0] = current_gaussian[0] + 10
                current_gaussian[1] = current_gaussian[1] + 10
                self.debug_print(fr"too many centroids ({centroids_count}), relaxing gaussian blur kernel: {current_gaussian[0]}/{current_gaussian[1]}")

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

        if self.args.artifacts_debug:
            debug_suffix = '__' + fr"{self.debug_counter:02d}"
            self.debug_counter += 1

            output_filename = re.sub(
                r"\.jpg",
                fr"{debug_suffix}_centroids_distances_sorted.txt",
                os.path.join(self.destination_path, os.path.basename(self.filename))
                )

            self.debug_print(fr"saving centroids_distances_sorted to: " + output_filename)
            with open(output_filename, "w") as f:
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

        # select % of the closest centroids as non-artifacts
        _, j = math.modf(len(centroids_distances_sorted) * self.args.artifacts_majority_threshold)
        j_min = len(centroids_distances_sorted) - j

        # there should be at least one centroid considered the subject of an image
        if j < 1:
            return {
                'error': fr"{self.args.artifacts_majority_threshold} is too low, try increasing",
                'image': self.images['original']
            }

        self.debug_print(fr"Majority: {j} centroids, minority: {j_min} centroids ({round(self.args.artifacts_majority_threshold * 100, 2)}%)")

        # Find the bounding rectangle of all centroids except artifacts
        x_min, y_min, x_max, y_max = float('inf'), float('inf'), 0, 0

        height, width = self.images['original_gray_blurred_edges'].shape

        # find the largest bounding rect without artifacts
        x1_left, y1_top, x2_right, y2_bottom = 0, 0, width, height

        prev_distance = None
        prev_distance_pct = None
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
                    prev_distance_pct = round((centroids_distances_sorted[i]['sum_distances'] - prev_distance) / prev_distance, 4)
                    if prev_distance_pct > self.args.artifacts_discontinuity_threshold:
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
                    fr"{i}: " + str(int(centroids_distances_sorted[i]['sum_distances'])) \
                            + fr" - {round(prev_distance_pct * 100, 2)} %"
                            + ("" if jump_centroid is None else " - JUMP")
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

        # rectangle with the minimum "empty" space around the subject of the image
        self.images['original_subject_min_space'] = self.images['original'][
            self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['y_min']: \
                self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['y_max'],
            self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['x_min']: \
                self.transforms['original_gray_blurred_edges_subject_min_space_centroids']['x_max']
            ]

        # rectangle with the maximum "empty" space around the subject of the image
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
        
    def empty_space_average_weighted_color(self):
        if self.transforms['original_gray_blurred_edges_subject_max_space_centroids'] is None:
            raise ValueError("requires detect_empty_space_edge_detection_canny to be run first in centroids mode")
        if self.transforms['original_gray_blurred_edges_subject_min_space_centroids'] is None:
            raise ValueError("requires detect_empty_space_edge_detection_canny to be run first in centroids mode")

        min_space = self.transforms['original_gray_blurred_edges_subject_min_space_centroids']
        max_space = self.transforms['original_gray_blurred_edges_subject_max_space_centroids']

        self.debug_print("min_space: " + str(min_space))
        self.debug_print("max_space: " + str(max_space))

        space_bottom = self.images['original'][min_space['y_max']:max_space['y_max'],:,:]
        space_top    = self.images['original'][max_space['y_min']:min_space['y_min'],:,:]
        space_left   = self.images['original'][:,max_space['x_min']:min_space['x_min'],:]
        space_right  = self.images['original'][:,min_space['x_max']:max_space['x_max'],:]

        self.images['original_subject_removed'] = self.images['original'].copy()
        self.images['original_subject_removed'][min_space['y_min']:min_space['y_max'],min_space['x_min']:min_space['x_max']] = [0,0,0]

        s1 = average_color(space_top)
        s2 = average_color(space_bottom)
        s3 = average_color(space_left)
        s4 = average_color(space_right)

        s_pixels = s1[1] + s2[1] + s3[1] + s4[1]
        if s_pixels > 0:
            b_avg = np.floor(0.5 +
                s1[0][0] * (s1[1] / s_pixels) + s2[0][0] * (s2[1] / s_pixels) + s3[0][0] * (s3[1] / s_pixels) + s4[0][0] * (s4[1] / s_pixels)
            )
            g_avg = np.floor(0.5 +
                s1[0][1] * (s1[1] / s_pixels) + s2[0][1] * (s2[1] / s_pixels) + s3[0][1] * (s3[1] / s_pixels) + s4[0][1] * (s4[1] / s_pixels)
            )
            r_avg = np.floor(0.5 +
                s1[0][2] * (s1[1] / s_pixels) + s2[0][2] * (s2[1] / s_pixels) + s3[0][2] * (s3[1] / s_pixels) + s4[0][2] * (s4[1] / s_pixels)
            )
        else:
            # default to white background
            b_avg = 255
            g_avg = 255
            r_avg = 255

        self.debug_print(fr"BGR avg: {b_avg} {g_avg} {r_avg}")
        self.debug_print(r"space_top" + str(average_color(space_top)))
        self.debug_print(r"space_bottom_avg" + str(average_color(space_bottom)))
        self.debug_print(r"space_left_avg" + str(average_color(space_left)))
        self.debug_print(r"space_right_avg" + str(average_color(space_right)))

        avg_bg_color = np.array([b_avg, g_avg, r_avg], dtype=np.uint8)

        longest_path = math.ceil(math.sqrt(
            (self.transforms['original_subject_min_space']['x_max'] - self.transforms['original_subject_min_space']['x_min'])**2 +
            (self.transforms['original_subject_min_space']['y_max'] - self.transforms['original_subject_min_space']['y_min'])**2
        ))

        self.debug_print(fr"longest_path: {longest_path}")

        longest_path = math.ceil(longest_path * (1 - math.cos(math.radians(MAX_ROTATION_ANGLE_DEGREES))) + self.args.canny_padding * 2)

        self.debug_print(fr"longest_path adjusted by the max rotation angle and padding: {longest_path}")

        self.images['original_extended'] = np.copy(self.images['original']).astype(np.uint8)
        self.transforms['original_extended_subject_min_space'] = self.transforms['original_subject_min_space']

        if self.transforms['original_subject_min_space']['x_max'] + longest_path > self.images['original'].shape[1]:
            diff = self.transforms['original_subject_min_space']['x_max'] + longest_path - self.images['original'].shape[1]
            right_extension = np.empty((self.images['original'].shape[0], diff, 3))
            right_extension[:,:] = avg_bg_color
            self.images['original_extended'] = np.hstack((self.images['original_extended'], right_extension)).astype(np.uint8)
            self.debug_print(fr"extended on the right by {diff} pixels")
        
        if self.transforms['original_subject_min_space']['x_min'] - longest_path < 0:
            diff = longest_path - self.transforms['original_subject_min_space']['x_min']
            left_extension = np.empty((self.images['original'].shape[0], diff, 3))
            left_extension[:,:] = avg_bg_color
            self.images['original_extended'] = np.hstack((left_extension, self.images['original_extended'])).astype(np.uint8)
            self.transforms['original_extended_subject_min_space']['x_min'] += diff
            self.transforms['original_extended_subject_min_space']['x_max'] += diff
            self.debug_print(fr"extended on the left by {diff} pixels")

        if self.transforms['original_subject_min_space']['y_max'] + longest_path > self.images['original'].shape[0]:
            diff = self.transforms['original_subject_min_space']['y_max'] + longest_path - self.images['original'].shape[0]
            bottom_extension = np.empty((diff, self.images['original_extended'].shape[1], 3))
            bottom_extension[:,:] = avg_bg_color
            self.images['original_extended'] = np.vstack((self.images['original_extended'], bottom_extension)).astype(np.uint8)
            self.debug_print(fr"extended at the bottom by {diff} pixels")

        if self.transforms['original_subject_min_space']['y_min'] - longest_path < 0:
            diff = longest_path - self.transforms['original_subject_min_space']['y_min']
            top_extension = np.empty((diff, self.images['original_extended'].shape[1], 3))
            top_extension[:,:] = avg_bg_color
            self.images['original_extended'] = np.vstack((top_extension, self.images['original_extended'])).astype(np.uint8)
            self.transforms['original_extended_subject_min_space']['y_min'] += diff
            self.transforms['original_extended_subject_min_space']['y_max'] += diff
            self.debug_print(fr"extended at the top by {diff} pixels")

        self.images['original_extended'][:self.transforms['original_extended_subject_min_space']['y_min'],:] = avg_bg_color
        self.images['original_extended'][self.transforms['original_extended_subject_min_space']['y_max']:,:] = avg_bg_color
        self.images['original_extended'][:,:self.transforms['original_extended_subject_min_space']['x_min']] = avg_bg_color
        self.images['original_extended'][:,self.transforms['original_extended_subject_min_space']['x_max']:] = avg_bg_color

        return {
            'error': None,
            'bgcolor_np': avg_bg_color,
            'bgcolor': (b_avg, g_avg, r_avg)
        }

    def enough_space_to_rotate(self):
        if self.transforms['original_subject_min_space'] is None:
            raise ValueError("enough_space_to_rotate requires detect_empty_space_edge_detection_canny to be run first")

        longest_path = math.ceil(math.sqrt(
            (self.transforms['original_subject_min_space']['x_max'] - self.transforms['original_subject_min_space']['x_min'])**2 +
            (self.transforms['original_subject_min_space']['y_max'] - self.transforms['original_subject_min_space']['y_min'])**2
        ))

        if self.transforms['original_subject_min_space']['x_max'] + longest_path > self.images['original'].shape[1]:

            diff = self.transforms['original_subject_min_space']['x_max'] + longest_path - self.images['original'].shape[1]

            self.images['temp'] = self.images['original']
            i = 0
            while self.images['temp'].shape[1] < self.images['original'].shape[1] + diff:
                i = i + 1
                cut_cols = min(
                    self.images['original'].shape[1] + diff - self.images['temp'].shape[1],
                    self.transforms['original_subject_min_space']['x_min']
                    )

                self.debug_print(fr"extending to the right by {cut_cols} pixel(s)")

                if i % 2 == 1:
                    cut_cols_left = max(
                        self.transforms['original_subject_min_space']['x_min'] - \
                            (self.images['original'].shape[1] + diff - self.images['temp'].shape[1]),
                        0
                    )
                    cut_cols_right = self.transforms['original_subject_min_space']['x_min']

                    # cut out the first {cut_cols} columns, returned as 3D array
                    # (Y ranges from 0 to height, X ranges from 0 to {cut_cols}, all 3 color channels))
                    #
                    # reverse order each odd iterations
                    first_cols_3d = np.fliplr(self.images['original'][:,cut_cols_left:cut_cols_right,:])
                else:
                    cut_cols_left = 0
                    cut_cols_right = min(
                        self.images['original'].shape[1] + diff - self.images['temp'].shape[1],
                        self.transforms['original_subject_min_space']['x_min']
                    )

                    # do not reverse order during even iterations
                    first_cols_3d = self.images['original'][:,cut_cols_left:cut_cols_right,:]

                # extend original image (or original image previously extended)
                # with the slice of required length
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

        lines = None

        current_gaussian = [
            self.args.canny_gaussian or self.args.canny_gaussian1,
            self.args.canny_gaussian or self.args.canny_gaussian2
            ]

        while lines is None and \
            current_gaussian[0] > self.args.canny_gaussian1_min and \
            current_gaussian[1] > self.args.canny_gaussian2_min :

            self.prepare_edges(gaussian_kernel = current_gaussian)

            hough_threshold = hough_threshold_initial
            hough_rho = hough_rho_resolution_pixels

            random.seed()

            # search for lines within the image, trying relaxing parameters a bit if none found
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

            # slightly tightening blur kernel
            if lines is None:
                current_gaussian[0] = current_gaussian[0] - 2
                current_gaussian[1] = current_gaussian[1] - 2
                self.debug_print(fr"did not find any lines, tightening gaussian blur kernel: {current_gaussian[0]}/{current_gaussian[1]}")

        if lines is None:
            return {
                'error': "No lines",
                'image': self.images['original']
            }

        sum_lines = 0
        sum_deviation = 0

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
            self.write('original_gray_blurred_edges_lines', '_gray_blurred_edges_lines')

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

def write_jpeg(filename, filedata, q = 85):
    cv2.imwrite(
        filename,
        filedata,
        [
            cv2.IMWRITE_JPEG_QUALITY, q,
#            cv2.IMWRITE_JPEG_SAMPLING_FACTOR, 0x111111
        ]
    )

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
        elif math.degrees(line_deviation) > MAX_ROTATION_ANGLE_DEGREES or math.degrees(line_deviation) < -1 * MAX_ROTATION_ANGLE_DEGREES:
            if args.hough_debug:
                print(fr"     DEBUG hough_filter_lines: line {i} is too inclined, excluding from sum_deviation calculation")
        else:
            if tmp_lines is None:
                tmp_lines = []

            tmp_lines.append(lines[i])

    return tmp_lines

def main():
    run_modes = (
        "trim-canny", "fix-rotation", "remove-artifacts", "clean-all", "enough-space-to-rotate",
        "image-info",
        "train-model",
        "contours-debug", "contours-min-distance-debug", "contours-loneliness",
        "format-multiple-documents"
    )

    parser = argparse.ArgumentParser()
    parser.add_argument('--filename', type=str)
    parser.add_argument('--source-file', type=str, default=None)
    parser.add_argument('--source-dir', type=str, default=None)
    parser.add_argument('--destination-dir', type=str, default=None)
    parser.add_argument('--run', type=str, default='', help=fr"mandatory, mode of operation. one of: {', '.join(run_modes)}")
    parser.add_argument('--canny-threshold1', type=int, default=10)
    parser.add_argument('--canny-threshold2', type=int, default=1)
    parser.add_argument('--canny-gaussian', type=int, default=None)
    parser.add_argument('--canny-gaussian1', type=int, default=71)
    parser.add_argument('--canny-gaussian2', type=int, default=71)
    parser.add_argument('--canny-gaussian1-min', type=int, default=41)
    parser.add_argument('--canny-gaussian2-min', type=int, default=41)
    parser.add_argument('--canny-padding', type=int, default=100)
    parser.add_argument('--canny-debug', type=bool, default=False)
    parser.add_argument('--hough-debug', type=bool, default=False)
    parser.add_argument('--hough-theta-resolution-degrees', default=0.1, type=float)
    parser.add_argument('--hough-rho-resolution-pixels', default=1, type=float, help='width of the detected line - min')
    parser.add_argument('--hough-rho-resolution-pixels-max', type=float, help='width of the detected line - max')
    parser.add_argument('--hough-threshold-initial', type=int, default=650, help='number of points in a line required to detect a line - max')
    parser.add_argument('--hough-threshold-minimal', type=int, help='number of points in a line required to detect a line - min')
    parser.add_argument('--copy-source-to-destination', type=bool, default=False)
    parser.add_argument('--skip-existing', type=bool, default=False, help='if destination exists, do not overwrite')
    parser.add_argument('--clean-existing', type=bool, default=False, help='if destination image and/or related debug exists, clean it')
    parser.add_argument('--artifacts-debug', type=bool, default=False)   
    parser.add_argument('--artifacts-majority-threshold', type=float, default=0.99, help="%% of centroids by artifact measure not considered artifacts")
    parser.add_argument('--artifacts-discontinuity-threshold', type=float, default=0.07, help="%% of measure jump considered discontinuity")
    parser.add_argument('--dilation-kernel-h', type=int, default=50)
    parser.add_argument('--dilation-kernel-w', type=int, default=50)
    parser.add_argument('--show-contour-shortest-paths', type=int, default=None)
    parser.add_argument('--shortest-path-exponential', type=bool, default=True)
    parser.add_argument('--loneliness-threshold', type=float, default=0.999)
    parser.add_argument('--fill-contour', type=int, default=None)
    parser.add_argument('--jpeg-quality', type=int, default=85)
    parser.add_argument('--debug', type=bool, default=False)
    parser.add_argument('--debug-no-intermediate-images', type=bool, default=False)
    parser.add_argument('--debug-log', type=bool, default=False)
    parser.add_argument('--train-path-up', type=str, default='')
    parser.add_argument('--train-path-down', type=str, default='')
    parser.add_argument('--check-orientation', type=str, default='')
    args = parser.parse_args()

    if (args.run not in run_modes):
        parser.print_help()
        print("\n" fr"Need --run with one of: {', '.join(run_modes)}" "\n")
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

    if args.run == r"format-multiple-documents":
        if args.destination_dir is None or not os.path.isdir(args.destination_dir):
            parser.print_help()
            print("\n" fr"format-multiple-documents requires --destination-dir which exists!" "\n")
            sys.exit(2)

        for afn in os.listdir(args.destination_dir):
            # ^(OF|of|NVF|nvf|ОФ|НВФ)[\-\ ]{1,2}(\d+?)[\-\ \_](\d[\d_,;\-\ \.]*?)[-_]([\d_]+?)[^\d]?.*?(\.jpg)$
            if not (s := re.search(r"^((OF|of|NVF|nvf|ОФ|НВФ)[\-\ ]{1,2}(\d+?)[\-\ \_](\d+)[\_]\d+)_formatted(\.[^\.]+)$", afn)):
                continue

            (filename_wo_ext, ofnvf, n1, n2, ext) = s.groups()
            canonical_document_dir = str.join("-", (str.lower(ofnvf), n1, n2))
            orig_name = filename_wo_ext + ext

            print(fr"{afn} -> {orig_name}")

            if os.path.isfile(os.path.join(args.destination_dir, orig_name)):
                if not os.path.isdir(os.path.join(args.destination_dir, canonical_document_dir)):
                    Path(os.path.join(args.destination_dir, canonical_document_dir)).mkdir(parents=True, exist_ok=True)

                if not os.path.isfile(os.path.join(args.destination_dir, canonical_document_dir, afn)):
                    shutil.copy2(os.path.join(args.destination_dir, afn), os.path.join(args.destination_dir, canonical_document_dir))

                    if os.path.isfile(os.path.join(args.destination_dir, ".debug.log")):
                        with open(os.path.join(args.destination_dir, ".debug.log"), 'r') as fin, \
                                open(os.path.join(args.destination_dir, canonical_document_dir, ".debug.log"), 'a') as fout:
                            for line in fin:
                                if re.search(fr" \[{filename_wo_ext}\] ", line) or \
                                    re.search(fr" \[ScannedPage.batch_log\].*(created target dir|started as)", line):
                                    fout.write(line)

        for d in os.listdir(args.destination_dir):
            if not os.path.isdir(os.path.join(args.destination_dir, d)):
                continue

            if not(s := re.search(r"^([a-z]+\-\d+\-\d+)$", d)):
                continue

            for afn in os.listdir(os.path.join(args.destination_dir, d)):
                if afn != r".debug.log":
                    continue

                compressed_filename = compress_file(os.path.join(args.destination_dir, d, afn))
                print(fr"{os.path.join(args.destination_dir, d, afn)} -> {compressed_filename}")
                if os.path.isfile(compressed_filename):
                    os.remove(os.path.join(args.destination_dir, d, afn))
                    print(fr"cleaned up {os.path.join(args.destination_dir, d, afn)}")
                else:
                    print(fr"{compressed_filename} - does not exist")

            for afn in os.listdir(args.destination_dir):
                if afn == r".debug.log":
                    continue

                if os.path.isfile(os.path.join(args.destination_dir, afn)) and re.search(r"^\.", afn):
                    shutil.copy2(os.path.join(args.destination_dir, afn), os.path.join(args.destination_dir, d))

        sys.exit(0)


    if (args.source_dir is not None) + (args.filename is not None) + (args.source_file is not None) > 1:
        parser.print_help()
        print(
            "\n"
            fr"Choose only one of:" "\n"
            fr"    --filename    - to process one file" "\n"
            fr"    --source-dir  - to process a directory" "\n"
            fr"    --source-file - to process filenames from a text file" "\n"
            )
        sys.exit(2)
    if args.source_dir is not None and args.destination_dir is None:
        parser.print_help()
        print("\n" fr"Specifying --source-dir implies specifying --destination-dir!" "\n")
        sys.exit(2)

    files_to_process = []

    if args.source_file is not None:
        if not os.path.isfile(args.source_file):
            parser.print_help()
            print("\n" fr"Non-existent source-file specified: [{args.source_file}]" "\n")
            sys.exit(2)

        destination_dir = args.destination_dir if args.destination_dir is not None else os.path.dirname(args.source_file)
        print (fr"reading {args.source_file}")
        with open(args.source_file, 'r') as afile:
            for aline in afile:
                if not os.path.isfile(os.path.join(destination_dir, aline.strip())):
                    print ("SKIPPING non-existent file:", os.path.join(destination_dir, aline.strip()))
                else:
                    files_to_process.append({
                        'input_filename': os.path.join(destination_dir, aline.strip()),
                        'destination_dir': destination_dir
                    })

    if args.source_dir is not None:
        if not os.path.isdir(args.source_dir):
            parser.print_help()
            print("\n" fr"Non-existent directory specified: [{args.source_dir}]" "\n")
            sys.exit(2)

        for afn in os.listdir(args.source_dir):
            if not re.search(r"\.(jpg|png)$", afn, re.IGNORECASE):
                print ("SKIPPING non-image files:", os.path.join(args.source_dir, afn))
                continue

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

    counter = 0
    counter_string = ""
    logged_run = False
    for afile in files_to_process:
        counter = counter + 1
        counter_string = str(counter) + "/" + str(len(files_to_process))

        args.destination_dir = afile['destination_dir']
        input_filename = afile['input_filename']

        print (str(datetime.datetime.now()) + " " + fr"working on {input_filename} [{counter_string}] saving to {args.destination_dir}")

        ascan = ScannedPage(input_filename, args = args)

        if args.run == r"contours-loneliness":
            res = ascan.dilated_image_contours_loneliness(bgcolor=(0,0,0))
            if (res['error']):
                raise ValueError(res['error'])

        if args.run == r"contours-min-distance-debug":
            res = ascan.dilated_image_min_distance()

        if args.run == r"contours-debug":
            res = ascan.dilated_image_contours_debug()
            if (res['error']):
                raise ValueError(res['error'])

            if args.show_contour_shortest_paths is not None:
                output_filename = ascan.output_filename('', '__contours-debug-' + str(args.show_contour_shortest_paths))
            else:
                output_filename = ascan.output_filename('_contours-debug')

            cv2.imwrite(
                output_filename,
                res['image'],
                [cv2.IMWRITE_JPEG_QUALITY, 85]
                )
            print (str(datetime.datetime.now()) + " written " + ascan.output_filename('contours-debug'))

        if args.run == r"enough-space-to-rotate":
            res = ascan.detect_empty_space_edge_detection_canny()
            if (res['error']):
                raise ValueError(res['error'])
            
            res = ascan.empty_space_average_weighted_color()
            if (res['error']):
                raise ValueError(res['error'])

            ascan.write('original_subject_removed', debug = False)
            ascan.write('original_extended', debug = False)
        if args.run == r"remove-artifacts":
            if args.skip_existing and os.path.isfile(ascan.output_filename('original_subject_max_space')):
                print(str(datetime.datetime.now()) + fr" skipping existing " + str(ascan.output_filename('original_subject_max_space')))
                continue

            res = ascan.detect_artifacts()
            if res['error']:
                raise ValueError(res['error'])
            else:
                ascan.write('original_subject_max_space', debug = False)
        if args.run == r"trim-canny":
            if args.skip_existing and os.path.isfile(ascan.output_filename('original_subject_min_space_padded')):
                print(str(datetime.datetime.now()) + fr" skipping existing " + str(ascan.output_filename('original_subject_min_space_padded')))
                continue

            res = ascan.detect_empty_space_edge_detection_canny()
            if (res['error']):
                raise ValueError(res['error'])
            else:
                ascan.write('original_subject_min_space_padded', debug = False)
        if args.run == r"fix-rotation":
            if args.skip_existing and os.path.isfile(ascan.output_filename('original_rotated')):
                print(str(datetime.datetime.now()) + fr" skipping existing " + str(ascan.output_filename('original_rotated')))
                continue

            res = ascan.detect_image_rotation_canny_hough()
            if (res['error'] == 'No lines'):
                ascan.write('original', debug = False)
            elif (res['error']):
                raise ValueError(res['error'])
            else:
                ascan.write('original_rotated', debug = False)
        if args.run == r"clean-all":
            if args.skip_existing and os.path.isfile(ascan.output_filename('original_subject_min_space_padded',  "_formatted")):
                print(str(datetime.datetime.now()) + fr" skipping existing " + str(ascan.output_filename('original_subject_min_space_padded',  "_formatted")))
                continue

            # check if the original image subject "touches" side of the picture:
            # if it doest - can't rotate it
            res = ascan.detect_empty_space_edge_detection_canny()
            if (res['error'] == 'Blank image'):
                ascan.write('original', "_formatted", debug = False)
                ascan.batch_log(fr"{counter_string} blank image, copied as is")
                continue
            elif (res['error']):
                raise ValueError(res['error'])
            
            bgcolor = None
            res = ascan.empty_space_average_weighted_color()
            if (res['error']):
                raise ValueError(res['error'])
            else:
                bgcolor = res['bgcolor']

            ascan_extended = ScannedPage(input_filename, args = args)
            ascan_extended.images['original'] = ascan.images['original_extended']

            # TBD: check if no empty space has been found at all 
            #
#            if not ascan.subject_touches_frames():
#               ascan.debug_print(fr"subject doesn't touch the frame, can apply rotation")

            res = ascan_extended.detect_image_rotation_canny_hough()
            if res['error'] and res['error'] != 'No lines':
                raise ValueError(res['error'])

            # treated rotated image as original
            ascan_transformed = ScannedPage(input_filename, args = args)
            if res['error'] == 'No lines':
                ascan_transformed.batch_log(fr"{counter_string} no lines detected in the image, not rotating")
                ascan_transformed.images['original'] = ascan_extended.images['original']
            else:
                ascan_transformed.images['original'] = ascan_extended.images['original_rotated']

            # trim rotate image using centroids with artifact detection
            res = ascan_transformed.detect_empty_space_edge_detection_canny()
            if (res['error'] == 'Blank image'):
                ascan.write('original', "_formatted", debug = False)
                ascan.batch_log(fr"{counter_string} blank image, copied as is")
                continue
            elif (res['error']):
                raise ValueError(res['error'])

            ascan_shaded = ScannedPage(input_filename, args = args)
            ascan_shaded.images['original'] = ascan_transformed.images['original_subject_min_space_padded']
            res = ascan_shaded.dilated_image_contours_loneliness(bgcolor)

            if not res['error'] and res['shaded_areas'] > 0:
                ascan_final = ScannedPage(input_filename, args = args)
                ascan_final.images['original'] = ascan_shaded.images['original_outliers_removed']

                res = ascan_final.detect_empty_space_edge_detection_canny()
                if (res['error']):
                    raise ValueError(res['error'])

                ascan_final.write('original_subject_min_space_padded', "_formatted", debug = False)
            else:
                ascan_transformed.write('original_subject_min_space_padded', "_formatted", debug = False)

            ascan.batch_log(fr"{counter_string} processed")

if __name__ == "__main__":
    main()
