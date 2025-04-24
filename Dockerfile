FROM --platform=linux/arm64 ruby:2.7.8

ENV RAILS_ENV=production
ENV RACK_ENV=production

# RUN apt-get update && apt-get install -y \
#     build-essential \
#     libxml2-dev \
#     libxslt-dev \
#     pkg-config \
#     zlib1g-dev \
#     liblzma-dev \
#     patch \
#     && rm -rf /var/lib/apt/lists/*

WORKDIR /

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]