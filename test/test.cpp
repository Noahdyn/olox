#include <cstdio>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <array>
#include <vector>
#include <filesystem>
#include <regex>
#include <fstream>
#include <sstream>

const std::string GREEN = "\033[1;32m";
const std::string RED = "\033[1;31m";
const std::string RESET = "\033[0m";
std::regex EXPECT_PATTERN(R"(//\s*expect:\s*(.+))");

std::string exec(const std::string& cmd) {
    std::array<char, 128> buffer;
    std::string result;
    std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(cmd.c_str(), "r"), pclose);
    if (!pipe) {
        throw std::runtime_error("popen() failed!");
    }
    while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe.get()) != nullptr) {
        result += buffer.data();
    }
    return result;
}

std::vector<std::string> get_expected_values(const std::string& filename) {
    std::vector<std::string> expectations;
    std::ifstream file(filename);
    std::string line;
    
    std::smatch match;
    
    while (std::getline(file, line)) {
        if (std::regex_search(line, match, EXPECT_PATTERN)) {
            std::string expected = match[1].str();
            expected.erase(expected.find_last_not_of(" \t\r\n") + 1);
            expectations.push_back(expected);
        }
    }
    
    return expectations;
}

std::vector<std::string> split_lines(const std::string& str) {
    std::vector<std::string> lines;
    std::istringstream stream(str);
    std::string line;
    
    while (std::getline(stream, line)) {
        line.erase(line.find_last_not_of(" \t\r") + 1);
        if (!line.empty()) {  
            lines.push_back(line);
        }
    }
    
    return lines;
}


int main(int argc, char* argv[]) {
    std::vector<std::string> passed;
    std::vector<std::string> failed;
    if (argc != 2) {
        std::cout << "Usage: " << argv[0] << " <path to interpreter>" << std::endl;
        return 1;
    }

    std::string interpreter_path = argv[1];
    std::vector<std::string> lox_files;

    for (const auto& entry : std::filesystem::recursive_directory_iterator("test")) {
        if (entry.is_regular_file() && entry.path().extension() == ".lox") {
            lox_files.push_back(entry.path().string());
        }
    }

    for (const std::string& lox_file : lox_files) {
        std::cout << "Testing " << lox_file << std::endl;
        std::string output = exec(interpreter_path + " " + lox_file);
        auto expectations = get_expected_values(lox_file);
        auto structured_output = split_lines(output);

        if (expectations.size() != structured_output.size()) {
            failed.push_back(lox_file);
            continue;
        }

        for (size_t i = 0; i<expectations.size(); i++) {
            if (expectations[i] != structured_output[i]) {
                failed.push_back(lox_file);
                goto next_file;
            }
        }

        passed.push_back(lox_file);
        next_file:;

    }

    for (const std::string pass : passed) {
        std::cout << GREEN << "✓ " << pass << RESET << std::endl;
    }

    for (const std::string& fail : failed) {
        std::cout << RED << "✗ " << fail << RESET << std::endl;
    }

    std::cout << "\n";
    std::cout << GREEN << "Passed: " << passed.size() << RESET << std::endl;
    std::cout << RED << "Failed: " << failed.size() << RESET << std::endl;
    
    return failed.empty() ? 0 : 1;

}

