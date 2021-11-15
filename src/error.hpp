#ifndef __MINEX_ERROR_H
#define __MINEX_ERROR_H

#include <exception>
#include <string>

struct minex_error : public std::exception
{
    minex_error(const std::string &msg) : what_(msg)
    {
    }
    const char *what() const noexcept override
    {
        return what_.c_str();
    }

private:
    std::string what_;
};

#endif