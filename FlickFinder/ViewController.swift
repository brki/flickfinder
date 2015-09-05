//
//  ViewController.swift
//  FlickFinder
//
//  Created by Brian King on 28/08/15.
//  Copyright (c) 2015 Brian King. All rights reserved.
//

import UIKit

class ViewController: UIViewController, UITextFieldDelegate {

	enum SearchType: Int {
		case Text, Geo
	}

	@IBOutlet weak var imageView: UIImageView!
	@IBOutlet weak var textSearchField: UITextField!
	@IBOutlet weak var latitudeField: UITextField!
	@IBOutlet weak var longitudeField: UITextField!
	@IBOutlet weak var imageTitle: UILabel!
	@IBOutlet weak var instructionLabel: UILabel!
	@IBOutlet weak var scrollView: UIScrollView!
	@IBOutlet weak var contentView: UIView!

	var isRotating = false
	var heightConstraint: NSLayoutConstraint?
	var activeTextField: UITextField?
	var textSearchBucket: JsonBucket!
	var geoSearchBucket: JsonBucket!
	var textSearchChanged = false
	var latLongSearchChanged = false
	var waitingForSearchResults: SearchType?
	let bucketCapacity = 1000  // Be aware: Flickr only returns the 4000 first results, so don't set this over 4000!

	let FLICKR_BASE_URL = "https://api.flickr.com/services/rest/"
	let FLICKR_API_KEY = "911f85901e54879bf46dc72eb42df31c"

	lazy var FLICKR_DEFAULTS: [String: String] = [
		"api_key": self.FLICKR_API_KEY,
		"format": "json",
		"nojsoncallback": "1",
		"extras": "url_m"
	]

    override func viewDidLoad() {
        super.viewDidLoad()

		// Set textField delegates
		textSearchField.delegate = self
		latitudeField.delegate = self
		longitudeField.delegate = self

		// Add constraints for the content view, which can not be done in the storyboard (pinning left/right edges to self.view,
		// setting the height constraint based on the view size and the status bar size).
		let leftConstraint = NSLayoutConstraint(
			item: contentView,
			attribute: NSLayoutAttribute.Leading,
			relatedBy: NSLayoutRelation.Equal,
			toItem: view,
			attribute: NSLayoutAttribute.Leading,
			multiplier: 1,
			constant: 0)
		let rightConstraint = NSLayoutConstraint(
			item: contentView,
			attribute: NSLayoutAttribute.Trailing,
			relatedBy: NSLayoutRelation.Equal,
			toItem: view,
			attribute: NSLayoutAttribute.Trailing,
			multiplier: 1,
			constant: 0)

		heightConstraint = NSLayoutConstraint(
			item: contentView,
			attribute: NSLayoutAttribute.Height,
			relatedBy: NSLayoutRelation.Equal,
			toItem: nil,
			attribute: NSLayoutAttribute.NotAnAttribute,
			multiplier: 1,
			constant: UIScreen.mainScreen().bounds.size.height - UIApplication.sharedApplication().statusBarFrame.size.height)

		view.addConstraints([leftConstraint, rightConstraint, heightConstraint!])

		textSearchBucket = JsonBucket(capacity: bucketCapacity)
		geoSearchBucket = JsonBucket(capacity: bucketCapacity)
    }

	/**
	Set the content view height constraint based on the space available.
	*/
	func setHeightConstraintIfNeeded() {
		if let constraint = heightConstraint {
			let currentStatusBarHeight = UIApplication.sharedApplication().statusBarFrame.size.height
			if currentStatusBarHeight != constraint.constant {
				constraint.constant = UIScreen.mainScreen().bounds.size.height - currentStatusBarHeight
			}
		}
	}

	/**
	The status bar may or may not be visible in the new orientation.
	Keep track of the rotation status.  When the keyboard is present, some UIKeyboardWillChangeFrameNotification
	notifications are sent during rotation, but we can ignore those.
	*/
	override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)
		isRotating = true
		coordinator.animateAlongsideTransition(
			{ context in
				self.setHeightConstraintIfNeeded()
			},
			completion: { context in
				self.isRotating = false
		})
	}

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
		imageView.image = nil
    }

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardChangingSize:", name: UIKeyboardWillChangeFrameNotification, object: nil)
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "statusBarChangingSize:", name: UIApplicationWillChangeStatusBarFrameNotification, object: nil)
	}

	override func viewWillDisappear(animated: Bool) {
		super.viewWillDisappear(animated)
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	@IBAction func viewTapped(sender: UITapGestureRecognizer) {
		// Could call view.endEditing(true) here, but we know the currently active field.
		activeTextField?.resignFirstResponder()
	}

	@IBAction func searchByText(sender: UIButton) {
		if textSearchChanged {
			prepareForNewSearchOfType(.Text)
			textSearchChanged = false

			var parameters: [String: String] = [
				"text": textSearchField.text,
				"per_page": "400"
			]
			fillBucket(textSearchBucket, ofType: .Text, parameters: parameters)
		} else {
			displayNextPhotoFromBucket(textSearchBucket)
		}
	}
	
	@IBAction func searchBylongitudeLatitude(sender: UIButton) {
		if latLongSearchChanged {
			if let latitude = latitudeField.text.toDouble(), longitude = longitudeField.text.toDouble() {
				if latitude > 90 || latitude < -90 {
					imageTitle.text = "latitude must be between -90 and 90"
				} else if longitude > 180 || longitude < -180 {
					imageTitle.text = "longitude must be between -180 and 180"
				} else {
					latLongSearchChanged = false
					prepareForNewSearchOfType(.Geo)
					let bbox = boundingBox(latitude: latitude, longitude: longitude)
					var parameters: [String: String] = [
						"bbox": bbox,
						"per_page": "250"
					]
					fillBucket(geoSearchBucket, ofType: .Geo, parameters: parameters)
				}
			} else {
				imageTitle.text = "Check that lat/long are valid numbers"
			}
		} else {
			displayNextPhotoFromBucket(geoSearchBucket)
		}
	}

	func prepareForNewSearchOfType(searchType: SearchType) {
		hideKeyboard()
		imageTitle.text = ""
		waitingForSearchResults = searchType
		switch searchType {
		case .Text:
			textSearchBucket.empty()
		case .Geo:
			geoSearchBucket.empty()
		}
	}

	/**
	Add results to bucket.
	Calls self.checkBucketContents() when some results have been fetched (or there are no results)
	This may call itself, if so, it will be running on a background thread.
	*/
	func fillBucket(bucket: JsonBucket, ofType searchType: SearchType, var parameters: [String: String], page: Int = 1) {
		parameters["page"] = "\(page)"
		let url = self.flickrURLForMethod("flickr.photos.search", withParameters: parameters)
		if url == nil {
			println("Unable to generate URL")
			return
		}
		let session = NSURLSession.sharedSession()
		let request = NSURLRequest(URL: url!)
		let task = session.dataTaskWithRequest(request) { data, response, error in
			if error != nil {
				println("Error with request processing: \(error)")
			} else {
				var error: NSError?
				let json = NSJSONSerialization.JSONObjectWithData(data, options: nil, error: &error) as! [String: AnyObject]
				if let err = error {
					println("Error converting received data to JSON: \(err)")
				} else {
					if let photos = json["photos"] as? [String: AnyObject], let photoList = photos["photo"] as? [[String: AnyObject]] {
						if photoList.count > 0 {
							bucket.add(photoList)
							self.checkBucketContents(bucket, ofType:searchType)
							if !bucket.isFull && self.morePhotosExist(currentPage: page, json: json) {
								self.fillBucket(bucket, ofType: searchType, parameters: parameters, page: page + 1)
							}
						} else {
							// empty bucket ... deal with it.
							self.checkBucketContents(bucket, ofType:searchType)
						}
					} else {
						println("Error extracting photos information")
					}
				}
			}
		}
		task.resume()

	}

	/**
	Notification handler called when something is in the bucket (or there was nothing to add to the bucket).

	This is called from a non-main thread.
	*/
	func checkBucketContents(bucket: JsonBucket, ofType searchType: SearchType) {
		if let waitingForType = waitingForSearchResults {
			if waitingForType == searchType {
				waitingForSearchResults = nil
				dispatch_async(dispatch_get_main_queue()) {
					self.displayNextPhotoFromBucket(bucket)
				}
			}
		}
	}

	func morePhotosExist(#currentPage: Int, json: [String: AnyObject]) -> Bool {
		var pages: Int = 0
		if let pageCount = json["pages"] as? String {
			if let pageCountInt = pageCount.toInt() {
				pages = pageCountInt
			} else {
				println("Unparseable value for 'pages': \(pageCount)")
			}
		} else if let pageCount = json["pages"] as? Int {
			pages = pageCount
		}
		return pages < currentPage
	}

	func displayNextPhotoFromBucket(bucket: JsonBucket) {
		if bucket.count == 0 {
			updateImageAndTitle(nil, title: "No photos found")
		} else {
			if let photo = bucket.take() {
				if let photoURL = photo["url_m"] as? String {
					dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)) {
						var titleText = (photo["title"] as? String ?? "")
						let image = self.imageFromURLString(photoURL)
						if image == nil {
							titleText = "Unable to fetch image (\(titleText))"
						}
						dispatch_async(dispatch_get_main_queue()) {
							self.updateImageAndTitle(image, title: titleText)
							self.instructionLabel.hidden = image != nil
						}
					}
				} else {
					println("url not found with expected key")
				}
			} else {
				updateImageAndTitle(nil, title: "Error getting photo from bucket")
			}
		}
	}

	func updateImageAndTitle(image: UIImage?, title: String) {
		imageTitle.text = title
		imageView.image = image
	}

	/**
	Get a bounding box around the given position.
	1 minute is approximately 1.85 kilometers.
	*/
	func boundingBox(#latitude: Double, longitude: Double, minutes: Double = 5) -> String {
		let offset = minutes / 60
		let minLatitude = wrapLatitude(latitude - offset)
		let maxLatitude = wrapLatitude(latitude + offset)
		let minLongitude = wrapLongitude(longitude - offset)
		let maxLongitude = wrapLongitude(longitude + offset)
		return "\(minLongitude),\(minLatitude),\(maxLongitude),\(maxLatitude)"
	}

	func wrapLatitude(value: Double) -> Double {
		if value < -90 || value > 90 {
			 return atan(sin(value) / abs(cos(value)))
		}
		return value
	}

	func wrapLongitude(value: Double) -> Double {
		if value < -180 || value > 180 {
			return atan2(sin(value), cos(value))
		}
		return value
	}

	func hideKeyboard() {
		if let textField = activeTextField {
			textField.resignFirstResponder()
		}
	}

	func imageFromURLString(string: String) -> UIImage? {
		if let url = NSURL(string: string) {
			if let data = NSData(contentsOfURL: url) {
				return UIImage(data: data)
			}
		}
		return nil
	}

	func flickrURLForMethod(method: String, withParameters customParameters: [String: String]) -> NSURL? {
		var parameters = FLICKR_DEFAULTS
		parameters["method"] = method
		for (key, value) in customParameters {
			parameters[key] = value
		}
		var queryItems = map(parameters) { NSURLQueryItem(name:$0, value:$1) }
		let components = NSURLComponents()
		components.queryItems = queryItems
		return NSURL(string: FLICKR_BASE_URL + "?" + (components.percentEncodedQuery ?? ""))
	}

	// MARK: Keyboard handlers

	func keyboardChangingSize(notification: NSNotification) {
		if isRotating {
			// No need to handle notifications during rotation
			return
		}
		if let userInfo = notification.userInfo as [NSObject: AnyObject]? {
			if let endFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.CGRectValue() {
				let convertedEndFrame = view.convertRect(endFrame, fromView: view.window)
				if convertedEndFrame.origin.y == view.bounds.height {
					// Keyboard is hidden.
					let contentInset = UIEdgeInsetsZero
					scrollView.contentInset = contentInset
					scrollView.scrollIndicatorInsets = contentInset
				} else {
					// Keyboard is visible.
					let animationDuration = userInfo[UIKeyboardAnimationDurationUserInfoKey] as? Double ?? 0.0
					let animationOption = userInfo[UIKeyboardAnimationCurveUserInfoKey] as? UIViewAnimationOptions ?? UIViewAnimationOptions.TransitionNone
					let keyboardTop = convertedEndFrame.origin.y

					if let textField = activeTextField {
						var textFieldRect = textField.convertRect(textField.bounds, toView: view)
						let textFieldBottom = textFieldRect.origin.y + textFieldRect.height
						let offset = textFieldBottom - keyboardTop
						if offset > 0 {
							let contentInset = UIEdgeInsets(top:0.0, left:0.0, bottom:convertedEndFrame.height, right:0.0)
							scrollView.contentInset = contentInset
							scrollView.scrollIndicatorInsets = contentInset
							UIView.animateWithDuration(
								animationDuration,
								delay: 0.0,
								options: animationOption,
								animations: {
									self.scrollView.scrollRectToVisible(textFieldRect, animated: false)
								},
								completion: nil)
						}
					}
				}
			}
		}
	}

	// MARK: Status bar handler
	func statusBarChangingSize(notification: NSNotification) {
		setHeightConstraintIfNeeded()
	}

	// MARK: UITextFieldDelegate methods:

	func textFieldShouldReturn(textField: UITextField) -> Bool {
		textField.resignFirstResponder()
		return true
	}

	func textFieldDidBeginEditing(textField: UITextField) {
		activeTextField = textField
	}

	func textFieldDidEndEditing(textField: UITextField) {
		if activeTextField == textField {
			activeTextField = nil
		}
	}

	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if textField == textSearchField {
			textSearchChanged = true
		} else {
			latLongSearchChanged = true
		}
		return true
	}
}

