FROM --platform=linux/arm64 ruby:3.4.3

WORKDIR /app

COPY Gemfile Gemfile.lock ./

# RUN gem install bundler -v 2.4.22
# RUN bundle config build.nokogiri --use-system-libraries
# RUN bundle config force_ruby_platform true
RUN bundle install
COPY . .

EXPOSE 3131

CMD ["bundle", "exec", "rails", "server", "-p", "3131", "-b", "0.0.0.0", "-e", "production"]