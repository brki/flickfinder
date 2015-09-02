//
//  ViewController.swift
//  FlickFinder
//
//  Created by Brian King on 28/08/15.
//  Copyright (c) 2015 Brian King. All rights reserved.
//

import UIKit

class ViewController: UIViewController, UITextFieldDelegate {

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

	let FLICKR_BASE_URL = "https://api.flickr.com/services/rest/"
	let FLICKR_API_KEY = "911f85901e54879bf46dc72eb42df31c"

	lazy var FLICKR_DEFAULTS: Dictionary<String, String> = [
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
			toItem: view,
			attribute: NSLayoutAttribute.Height,
			multiplier: 1,
			constant: -UIApplication.sharedApplication().statusBarFrame.size.height)

		view.addConstraints([leftConstraint, rightConstraint, heightConstraint!])
    }

	func setHeightConstraintIfNeeded() {
		if let constraint = heightConstraint {
			let currentStatusBarHeight = UIApplication.sharedApplication().statusBarFrame.size.height
			if currentStatusBarHeight != constraint.constant {
				constraint.constant = -currentStatusBarHeight
			}
		}
	}

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
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardChangingSize:", name: UIKeyboardWillChangeFrameNotification, object: nil)
	}

	override func viewWillDisappear(animated: Bool) {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	@IBAction func searchByText(sender: UIButton) {
		hideKeyboard()
		var parameters: [String: String] = [
			"text": textSearchField.text
		]

		if let url = flickrURLForMethod("flickr.photos.search", withParameters: parameters) {
			let session = NSURLSession.sharedSession()
			let request = NSURLRequest(URL: url)
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
							var titleText: String?
							var image: UIImage?

							if photoList.count > 0 {
								let index = Int(arc4random_uniform(UInt32(photoList.count)))
								let photo = photoList[index]
								if let photoURL = photo["url_m"] as? String {
									titleText = (photo["title"] as? String ?? "")
									image = self.imageFromURLString(photoURL)
									if image == nil {
										println("Unable to fetch image")
									}
								} else {
									println("url not found with expected key")
								}
							} else {
								titleText = "No photos found"
							}

							dispatch_async(dispatch_get_main_queue()) {
								self.imageTitle.text = titleText
								self.imageView.image = image
								self.instructionLabel.hidden = image != nil
							}
						} else {
							println("Error extracting photos information")
						}
					}
				}
			}
			task.resume()
		} else {
			println("Unable to generate URL")
		}
	}
	
	@IBAction func searchBylongitudeLatitude(sender: UIButton) {
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

}

