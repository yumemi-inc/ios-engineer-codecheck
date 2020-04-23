//
//  ViewController.swift
//  iOSEngineerCodeCheck
//
//  Created by 史 翔新 on 2020/04/20.
//  Copyright © 2020 YUMEMI Inc. All rights reserved.
//

import UIKit

class ViewController: UITableViewController, UISearchBarDelegate {

    @IBOutlet weak var SchBr: UISearchBar!
    
    var repositories: [[String: Any]] = []
    
    var data_task: URLSessionTask?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        SchBr.placeholder = "Tap here to search repositories with name."
        SchBr.delegate = self
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        data_task?.cancel()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        
        let word = searchBar.text!
        
        if word.count != 0 {
            let url = "https://api.github.com/search/repositories?q=\(word)"
            data_task = URLSession.shared.dataTask(with: URL(string: url)!) { (data, response, error) in
                let object = try! JSONSerialization.jsonObject(with: data!) as! [String: Any]
                let items = object["items"] as! [[String: Any]]
                self.repositories = items
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
            data_task?.resume()
        }
        
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "Detail" {
            let cell = sender as! UITableViewCell
            let indexPath = tableView.indexPath(for: cell)!
            let repository = repositories[indexPath.row]
            let detail = segue.destination as! ViewController2
            detail.repository = repository
        }
        
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return repositories.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Repository", for: indexPath)
        let repository = repositories[indexPath.row]
        cell.textLabel?.text = repository["full_name"] as? String
        cell.detailTextLabel?.text = repository["language"] as? String
        return cell
        
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let cell = tableView.cellForRow(at: indexPath)
        performSegue(withIdentifier: "Detail", sender: cell)
        
    }
    
}
