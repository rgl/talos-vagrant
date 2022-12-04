# syntax=docker/dockerfile:1.4
FROM node:18-alpine
WORKDIR /app
RUN npm install meshcommander@0.9.5-a
EXPOSE 4000
CMD ["/app/node_modules/.bin/meshcommander", "--any", "--port", "4000"]
